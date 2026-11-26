# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'json'
require 'vmpooler/api/rate_limiter'

describe Vmpooler::API::RateLimiter do
  let(:redis) { MockRedis.new }
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:config) { {} }
  let(:limiter) { described_class.new(app, redis, config) }
  let(:client) { Rack::MockRequest.new(limiter) }
  let(:ip) { '10.0.0.1' }
  let(:ip_key) { "vmpooler__ratelimit__global_per_ip__ip:#{ip}" }

  def get(path = '/api/v3/status', env = {})
    client.get(path, { 'REMOTE_ADDR' => ip }.merge(env))
  end

  describe 'when rate limiting is disabled' do
    let(:config) { { rate_limiting_enabled: false } }

    it 'passes every request through without touching redis' do
      expect(redis).not_to receive(:get)
      expect(redis).not_to receive(:pipelined)

      3.times { expect(get.status).to eq(200) }
    end
  end

  describe 'defaults' do
    it 'is enabled when the config does not say otherwise' do
      get
      expect(redis.get(ip_key).to_i).to eq(1)
    end

    it 'allows 100 requests a minute per IP' do
      expect(described_class::DEFAULT_LIMITS[:global_per_ip]).to eq(limit: 100, period: 60)
    end
  end

  describe 'counting requests' do
    it 'counts requests per client and expires the counter after the period' do
      2.times { get }

      expect(redis.get(ip_key).to_i).to eq(2)
      expect(redis.ttl(ip_key)).to be_between(1, 60)
    end

    it 'keeps a separate count for each IP' do
      get('/api/v3/status', 'REMOTE_ADDR' => '10.0.0.1')
      get('/api/v3/status', 'REMOTE_ADDR' => '10.0.0.2')
      get('/api/v3/status', 'REMOTE_ADDR' => '10.0.0.2')

      expect(redis.get('vmpooler__ratelimit__global_per_ip__ip:10.0.0.1').to_i).to eq(1)
      expect(redis.get('vmpooler__ratelimit__global_per_ip__ip:10.0.0.2').to_i).to eq(2)
    end

    it 'falls back to "unknown" when the request has no client address' do
      client.get('/api/v3/status')

      expect(redis.keys('vmpooler__ratelimit__*')).to eq(['vmpooler__ratelimit__global_per_ip__ip:unknown'])
    end
  end

  describe 'telling clients and endpoints apart' do
    it 'identifies a client with a token by the token, not the IP' do
      get('/api/v3/status', 'HTTP_X_AUTH_TOKEN' => 'abc123')

      expect(redis.keys('vmpooler__ratelimit__*')).to eq(['vmpooler__ratelimit__authenticated__token:abc123'])
    end

    it 'ignores an empty token and uses the IP' do
      get('/api/v3/status', 'HTTP_X_AUTH_TOKEN' => '')

      expect(redis.keys('vmpooler__ratelimit__*')).to eq(["vmpooler__ratelimit__authenticated__ip:#{ip}"])
    end

    it 'counts a VM request as a VM creation' do
      client.post('/api/v3/vm/debian-7-x86_64', 'REMOTE_ADDR' => ip)

      expect(redis.get("vmpooler__ratelimit__vm_creation__ip:#{ip}").to_i).to eq(1)
    end

    it 'counts a VM delete as a VM deletion' do
      client.delete('/api/v3/vm/host1', 'REMOTE_ADDR' => ip)

      expect(redis.get("vmpooler__ratelimit__vm_deletion__ip:#{ip}").to_i).to eq(1)
    end

    it 'counts a plain GET of a VM path against the general limit' do
      get('/api/v3/vm/host1')

      expect(redis.get(ip_key).to_i).to eq(1)
    end

    it 'tracks each endpoint type on its own' do
      client.post('/api/v3/vm/debian-7-x86_64', 'REMOTE_ADDR' => ip)
      get

      expect(redis.keys('vmpooler__ratelimit__*').length).to eq(2)
    end
  end

  describe 'when a client goes over its limit' do
    let(:config) { { rate_limits: { global_per_ip: { limit: 2, period: 30 } } } }
    let(:calls) { [] }
    let(:app) do
      lambda do |_env|
        calls << :called
        [200, {}, ['ok']]
      end
    end

    before { 2.times { get } }

    it 'answers 429 and does not run the app' do
      calls.clear
      response = get

      expect(response.status).to eq(429)
      expect(calls).to be_empty
    end

    it 'tells the client the limit and when to retry' do
      response = get

      expect(response.headers['X-RateLimit-Limit']).to eq('2')
      expect(response.headers['X-RateLimit-Remaining']).to eq('0')
      expect(response.headers['Retry-After'].to_i).to be_between(1, 30)
      expect(response.headers['X-RateLimit-Reset'].to_i).to be > Time.now.to_i - 1
      expect(response.headers['Content-Type']).to eq('application/json')
    end

    it 'explains it in a JSON body' do
      body = JSON.parse(get.body)

      expect(body).to include('ok' => false, 'error' => 'Rate limit exceeded', 'limit' => 2, 'period' => 30)
      expect(body['retry_after']).to be_between(1, 30)
    end

    it 'does not count the refused request' do
      3.times { get }

      expect(redis.get(ip_key).to_i).to eq(2)
    end

    it 'still lets another client through' do
      expect(get('/api/v3/status', 'REMOTE_ADDR' => '10.0.0.9').status).to eq(200)
    end
  end

  describe 'limits from the config' do
    let(:config) { { rate_limits: { vm_creation: { limit: 1, period: 10 } } } }

    it 'overrides only the types it names' do
      client.post('/api/v3/vm/debian-7-x86_64', 'REMOTE_ADDR' => ip)

      expect(client.post('/api/v3/vm/debian-7-x86_64', 'REMOTE_ADDR' => ip).status).to eq(429)
      expect(get.status).to eq(200)
    end

    it 'keeps the defaults for the others' do
      limit = limiter.instance_variable_get(:@config)

      expect(limit[:vm_deletion]).to eq(described_class::DEFAULT_LIMITS[:vm_deletion])
      expect(limit[:vm_creation]).to eq(limit: 1, period: 10)
    end
  end

  describe 'when redis fails' do
    it 'lets the request through if reading the count fails' do
      allow(redis).to receive(:get).and_raise(StandardError, 'redis is down')

      response = nil
      expect { response = get }.to output(/Rate limiter Redis error: redis is down/).to_stderr

      expect(response.status).to eq(200)
    end

    it 'lets the request through if counting it fails' do
      allow(redis).to receive(:pipelined).and_raise(StandardError, 'pipeline broke')

      response = nil
      expect { response = get }.to output(/Rate limiter increment error: pipeline broke/).to_stderr

      expect(response.status).to eq(200)
    end

    it 'falls back to the full period for Retry-After if the ttl cannot be read' do
      limited = described_class.new(app, redis, rate_limits: { global_per_ip: { limit: 1, period: 45 } })
      limited_client = Rack::MockRequest.new(limited)
      limited_client.get('/api/v3/status', 'REMOTE_ADDR' => ip)
      allow(redis).to receive(:ttl).and_raise(StandardError, 'no ttl')

      response = limited_client.get('/api/v3/status', 'REMOTE_ADDR' => ip)

      expect(response.status).to eq(429)
      expect(response.headers['Retry-After']).to eq('45')
    end
  end
end
