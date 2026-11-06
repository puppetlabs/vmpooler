# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V3 do
  include Rack::Test::Methods

  def app
    Vmpooler::API
  end

  after(:each) do
    Vmpooler::API.reset!
  end

  let(:config) do
    {
      config: {
        'site_name' => 'test pooler',
        'vm_lifetime_auth' => 2,
        'experimental_features' => true
      },
      pools: [
        { 'name' => 'pool1', 'size' => 5, 'template' => 'templates/pool1', 'clone_target' => 'default_cluster' },
        { 'name' => 'pool2', 'size' => 10 }
      ],
      statsd: { 'prefix' => 'stats_prefix' },
      alias: { 'poolone' => 'pool1' },
      pool_names: ['pool1', 'pool2', 'poolone']
    }
  end

  describe '/poolreset' do
    let(:prefix) { '/api/v3' }
    let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }

    let(:current_time) { Time.now }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, metrics, nil)
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /poolreset' do
      it 'refreshes ready and pending instances from a pool' do
        post "#{prefix}/poolreset", '{"pool1":"1"}'
        expect_json(true, 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistent pools' do
        post "#{prefix}/poolreset", '{"poolpoolpool":"1"}'
        expect_json(false, 400)
      end

      it 'resets multiple pools' do
        post "#{prefix}/poolreset", '{"pool1":"1","pool2":"1"}'
        expect_json(true, 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when not all pools exist' do
        post "#{prefix}/poolreset", '{"pool1":"1","pool3":"1"}'
        expect_json(false, 400)

        expected = {
          ok: false,
          bad_pools: ['pool3']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          post "#{prefix}/poolreset", '{"pool1":"1"}'
          expect_json(false, 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

      it 'should return 400 for invalid json' do
        post "#{prefix}/poolreset", '{"pool1":"1}'
        expect_json(false, 400)

        expected = { ok: false, message: 'JSON payload could not be parsed' }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'should return 400 with a bad pool name' do
        post "#{prefix}/poolreset", '{"pool11":"1"}'
        expect_json(false, 400)

        expected = { ok: false, bad_pools: ['pool11'] }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'should return 400 when there is no payload' do
        post "#{prefix}/poolreset"
        expect_json(false, 400)

        expected = { ok: false, message: 'JSON payload could not be parsed' }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end
    end
  end
end
