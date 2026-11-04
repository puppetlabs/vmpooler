# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'date'

describe Vmpooler::API::V3 do
  include Rack::Test::Methods

  def app
    Vmpooler::API
  end

  before(:each) do
    app.reset!
    Vmpooler::API::V3.clear_status_cache
  end

  let(:prefix) { '/api/v3' }
  let(:config) do
    {
      config: { 'site_name' => 'test pooler' },
      pools: [{ 'name' => 'pool1', 'size' => 5 }, { 'name' => 'pool2', 'size' => 10 }]
    }
  end
  let(:today) { Date.today.to_s }
  let(:yesterday) { (Date.today - 1).to_s }

  before(:each) do
    expect(app).to receive(:run!).once
    app.execute([:api], config, redis, nil, nil)
    app.settings.set :config, auth: false

    redis.hset("vmpooler__boot__#{today}", 'pool1:vm1', 10)
    redis.hset("vmpooler__boot__#{today}", 'pool1:vm2', 20)
    redis.hset("vmpooler__clone__#{today}", 'pool1:vm1', 5)
    redis.hset("vmpooler__tag__#{today}", 'vm1:created_by', 'jdoe')
    redis.hset("vmpooler__tag__#{today}", 'vm2:created_by', 'jdoe')
    redis.hset("vmpooler__tag__#{today}", 'vm1:project', 'x')
  end

  def json
    JSON.parse(last_response.body)
  end

  describe 'GET /vm' do
    it 'lists the pool names' do
      get "#{prefix}/vm"

      expect(last_response).to be_ok
      expect(last_response.header['Content-Type']).to eq('application/json')
      expect(json).to eq(%w[pool1 pool2])
    end
  end

  describe 'GET /summary' do
    it 'summarises boots, clones and tags for today by default' do
      get "#{prefix}/summary"

      expect(last_response).to be_ok
      expect(last_response.header['Content-Type']).to eq('application/json')
      expect(json['boot']['count']['total']).to eq(2)
      expect(json['boot']['duration']['total']).to eq(30.0)
      expect(json['clone']['count']['total']).to eq(1)
      expect(json['tag']['created_by']).to eq('jdoe' => 2, 'total' => 2)
      expect(json['tag']['project']).to eq('x' => 1, 'total' => 1)
    end

    it 'has one entry per day, with that day\'s boot, clone and tag data' do
      get "#{prefix}/summary"

      expect(json['daily'].length).to eq(1)
      day = json['daily'].first
      expect(day['date']).to eq(today)
      expect(day['boot']['count']['total']).to eq(2)
      expect(day['clone']['count']['total']).to eq(1)
      expect(day['tag']['created_by']['total']).to eq(2)
    end

    it 'covers a range of days' do
      redis.hset("vmpooler__clone__#{yesterday}", 'pool2:vm9', 7)

      get "#{prefix}/summary", from: yesterday, to: today

      expect(json['daily'].map { |d| d['date'] }).to eq([yesterday, today])
      expect(json['clone']['count']['total']).to eq(2)
    end

    it 'refuses a date that is not YYYY-MM-DD' do
      get "#{prefix}/summary", from: '01-05-2024'

      expect(last_response.status).to eq(400)
      expect(last_response.body).to match(/Invalid date format '01-05-2024', must match YYYY-MM-DD/)
    end

    it 'refuses a range that ends before it starts' do
      get "#{prefix}/summary", from: today, to: yesterday

      expect(last_response.status).to eq(400)
      expect(last_response.body).to match(/'to' cannot come before 'from'/)
    end

    it 'refuses a range that starts in the future' do
      tomorrow = (Date.today + 1).to_s

      get "#{prefix}/summary", from: tomorrow, to: (Date.today + 2).to_s

      expect(last_response.status).to eq(400)
      expect(last_response.body).to match(/'from' must be in the past/)
    end
  end

  describe 'GET /summary/:route' do
    it 'summarises boots, by pool' do
      get "#{prefix}/summary/boot"

      expect(last_response).to be_ok
      expect(json['boot']['count']['pool']['pool1']['total']).to eq(2)
      expect(json['boot']['duration']['pool']['pool1']['total']).to eq(30.0)
    end

    it 'summarises clones, by pool' do
      get "#{prefix}/summary/clone"

      expect(json['clone']['count']['pool']['pool1']['total']).to eq(1)
    end

    it 'summarises tags' do
      get "#{prefix}/summary/tag"

      expect(json['tag']['created_by']).to eq('jdoe' => 2, 'total' => 2)
    end

    it 'can give one part of a task' do
      get "#{prefix}/summary/boot/count"

      expect(json['boot'].keys).to eq(['count'])
    end

    it 'can give one tag' do
      get "#{prefix}/summary/tag/project"

      expect(json['tag'].keys).to eq(['project'])
    end

    it 'answers 404 for a route it does not know' do
      get "#{prefix}/summary/nonsense"

      expect(last_response.status).to eq(404)
      expect(json).to eq('ok' => false)
    end

    it 'checks the dates here too' do
      get "#{prefix}/summary/boot", from: 'yesterday'
      expect(last_response.status).to eq(400)

      get "#{prefix}/summary/boot", from: today, to: yesterday
      expect(last_response.status).to eq(400)

      get "#{prefix}/summary/boot", from: (Date.today + 1).to_s, to: (Date.today + 2).to_s
      expect(last_response.status).to eq(400)
    end
  end
end
