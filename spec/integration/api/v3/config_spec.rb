require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V3 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  # Added to ensure no leakage in rack state from previous tests.
  # Removes all routes, filters, middleware and extension hooks from the current class
  # https://rubydoc.info/gems/sinatra/Sinatra/Base#reset!-class_method 
  before(:each) do
    app.reset!
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
      pools_at_startup: [
        {'name' => 'pool1', 'size' => 5, 'template' => 'templates/pool1', 'clone_target' => 'default_cluster'},
        {'name' => 'pool2', 'size' => 10}
      ],
      statsd: { 'prefix' => 'stats_prefix'},
      alias: { 'poolone' => 'pool1' },
      pool_names: [ 'pool1', 'pool2', 'poolone' ]
    }
  }

  describe '/config/pooltemplate' do
    let(:prefix) { '/api/v3' }
    let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }

    let(:current_time) { Time.now }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, metrics, nil)
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'DELETE /config/pooltemplate/:pool' do
      it 'resets a pool template' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template"}'
        delete "#{prefix}/config/pooltemplate/pool1"
        expect_json(ok = true, http = 201)

        expected = {
          ok: true,
          template_before_reset: 'templates/new_template',
          template_before_overrides: 'templates/pool1'
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds when the pool has not been overridden' do
        delete "#{prefix}/config/pooltemplate/pool1"
        expect_json(ok = true, http = 200)
      end

      it 'fails on nonexistent pools' do
        delete "#{prefix}/config/pooltemplate/poolpoolpool"
        expect_json(ok = false, http = 404)
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          delete "#{prefix}/config/pooltemplate/pool1"
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

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
        expect_json(ok = false, http = 400)
      end

      it 'updates multiple pools' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template","pool2":"templates/new_template2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when not all pools exist' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"templates/new_template","pool3":"templates/new_template2"}'
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          bad_templates: ['pool3']
        }

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
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          bad_templates: ['pool1']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a template starts with /' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"/template1"}'
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          bad_templates: ['pool1']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a template ends with /' do
        post "#{prefix}/config/pooltemplate", '{"pool1":"template1/"}'
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          bad_templates: ['pool1']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          post "#{prefix}/config/pooltemplate", '{"pool1":"template/template1"}'
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

    end

    describe 'DELETE /config/poolsize' do
      it 'resets a pool size' do
        post "#{prefix}/config/poolsize", '{"pool1":"2"}'
        delete "#{prefix}/config/poolsize/pool1"
        expect_json(ok = true, http = 201)

        expected = {
          ok: true,
          pool_size_before_reset: 2,
          pool_size_before_overrides: 5
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a specified pool does not exist' do
        delete "#{prefix}/config/poolsize/pool10"
        expect_json(ok = false, http = 404)
        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds when a pool has not been overridden' do
        delete "#{prefix}/config/poolsize/pool1"
        expect_json(ok = true, http = 200)
        expected = {
          ok: true,
          pool_size_before_reset: 5,
          pool_size_before_overrides: 5
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          delete "#{prefix}/config/poolsize/pool1"
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
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
        expect_json(ok = false, http = 400)
        expected = {
          ok: false,
          not_configured: ['pool10']
        }

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
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          not_configured: ['pool1']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a negative value is provided for size' do
        post "#{prefix}/config/poolsize", '{"pool1":"-1"}'
        expect_json(ok = false, http = 400)

        expected = {
          ok: false,
          not_configured: ['pool1']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          post "#{prefix}/config/poolsize", '{"pool1":"1"}'
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end
    end

    describe 'POST /config/clonetarget' do
      it 'changes the clone target' do
        post "#{prefix}/config/clonetarget", '{"pool1":"cluster1"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'changes a pool size for multiple pools' do
        post "#{prefix}/config/clonetarget", '{"pool1":"cluster1","pool2":"cluster2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails when a specified pool does not exist' do
        post "#{prefix}/config/clonetarget", '{"pool10":"cluster1"}'
        expect_json(ok = false, http = 400)
        expected = {
          ok: false,
          bad_templates: ['pool10']
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds with 200 when no change is required' do
        post "#{prefix}/config/clonetarget", '{"pool1":"default_cluster"}'
        expect_json(ok = true, http = 200)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'succeeds with 201 when at least one pool changes' do
        post "#{prefix}/config/clonetarget", '{"pool1":"default_cluster","pool2":"cluster2"}'
        expect_json(ok = true, http = 201)

        expected = { ok: true }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'with experimental features disabled' do
        before(:each) do
          config[:config]['experimental_features'] = false
        end

        it 'should return 405' do
          post "#{prefix}/config/clonetarget", '{"pool1":"cluster1"}'
          expect_json(ok = false, http = 405)

          expected = { ok: false }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end
    end

    describe 'GET /config' do
      let(:prefix) { '/api/v3' }

      it 'returns pool configuration when set' do
        get "#{prefix}/config"

        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result['pool_configuration']).to eq(config[:pools])
      end
    end
  end
end
