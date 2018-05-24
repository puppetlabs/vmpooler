require 'spec_helper'
require 'rack/test'

module Vmpooler
  class API
    module Helpers
      def authenticate(auth, username_str, password_str)
        username_str == 'admin' and password_str == 's3cr3t'
      end
    end
  end
end

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  describe '/config/pooltemplate' do
    let(:prefix) { '/api/v1' }
    let(:metrics) { Vmpooler::DummyStatsd.new }
    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
        },
        pools: [
          {'name' => 'pool1', 'size' => 5, 'template' => 'templates/pool1'},
          {'name' => 'pool2', 'size' => 10}
        ],
        statsd: { 'prefix' => 'stats_prefix'},
        alias: { 'poolone' => 'pool1' },
        pool_names: [ 'pool1', 'pool2', 'poolone' ]
      }
    }

    let(:current_time) { Time.now }

    before(:each) do
      redis.flushdb

      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :metrics, metrics
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /config/pooltemplate' do
      it 'updates a pool template' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistent pools' do
        post "#{prefix}/config/pooltemplate", '{"poolpoolpool":"templates/newtemplate"}'
        expect_json(ok = false, http = 404)
      end

      it 'updates multiple pools' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template","pool2":"templates/new_template2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when not all pools exist' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template","pool3":"templates/new_template2"}'
        expect_json(ok = false, http = 404)

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'returns no changes when the template does not change' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/pool1"}'
        expect_json(ok = true, http = 200)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a invalid template parameter is provided' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"template1"}'
        expect_json(ok = false, http = 404)

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end
    end

    describe 'POST /config/poolsize' do
      it 'changes a pool size' do
        post "#{prefix}/config/poolsize", '{"pool1":"2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'changes a pool size for multiple pools' do
        post "#{prefix}/config/poolsize", '{"pool1":"2","pool2":"2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a specified pool does not exist' do
        post "#{prefix}/config/poolsize", '{"pool10":"2"}'
        expect_json(ok = false, http = 404)

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds with 200 when no change is required' do
        post "#{prefix}/config/poolsize", '{"pool1":"5"}'
        expect_json(ok = true, http = 200)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds with 201 when at least one pool changes' do
        post "#{prefix}/config/poolsize", '{"pool1":"5","pool2":"5"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a non-integer value is provided for size' do
        post "#{prefix}/config/poolsize", '{"pool1":"four"}'
        expect_json(ok = false, http = 404)

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end
    end

    describe 'GET /config' do
      it 'returns pool configuration when set' do
        get "#{prefix}/config"
        expect_json(ok = true, http = 200)
      end
    end
  end
end
