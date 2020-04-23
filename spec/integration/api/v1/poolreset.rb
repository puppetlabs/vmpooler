require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  after(:each) do
    Vmpooler::API.reset!
  end

  let(:config) {
    {
      config: {
        'site_name' => 'test pooler',
        'vm_lifetime_auth' => 2,
        'experimental_features' => true
      },
      pools: [
        {'name' => 'pool1', 'size' => 5, 'template' => 'templates/pool1', 'clone_target' => 'default_cluster'},
        {'name' => 'pool2', 'size' => 10}
      ],
      statsd: { 'prefix' => 'stats_prefix'},
      alias: { 'poolone' => 'pool1' },
      pool_names: [ 'pool1', 'pool2', 'poolone' ]
    }
  }

  describe '/poolreset' do
    let(:prefix) { '/api/v1' }
    let(:metrics) { Vmpooler::DummyStatsd.new }

    let(:current_time) { Time.now }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute(['api'], config, redis, metrics)
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /poolreset' do
      it 'refreshes ready and pending instances from a pool' do
        post "#{prefix}/poolreset", '{"pool1":"1"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistent pools' do
        post "#{prefix}/poolreset", '{"poolpoolpool":"1"}'
        expect_json(ok = false, http = 400)
      end

      it 'resets multiple pools' do
        post "#{prefix}/poolreset", '{"pool1":"1","pool2":"1"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when not all pools exist' do
        post "#{prefix}/poolreset", '{"pool1":"1","pool3":"1"}'
        expect_json(ok = false, http = 400)

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
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

      it 'should return 400 for invalid json' do
        post "#{prefix}/poolreset", '{"pool1":"1}'
        expect_json(ok = false, http = 400)

        expected = { ok: false }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'should return 400 with a bad pool name' do
        post "#{prefix}/poolreset", '{"pool11":"1"}'
        expect_json(ok = false, http = 400)

        expected = { ok: false }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'should return 404 when there is no payload' do
        post "#{prefix}/poolreset"
        expect_json(ok = false, http = 404)

        expected = { ok: false }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end
    end
  end
end
