require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  describe '/vm' do
    let(:prefix) { '/api/v1' }
    let(:metrics) { Vmpooler::DummyStatsd.new }
    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
        },
        pools: [
          {'name' => 'pool1', 'size' => 5},
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

    describe 'GET /vm/:hostname' do
      it 'returns correct information on a running vm' do
        create_running_vm 'pool1', 'abcdefghijklmnop'
        get "#{prefix}/vm/abcdefghijklmnop"
        expect_json(ok = true, http = 200)
        expected = {
          ok: true,
          abcdefghijklmnop: {
              template: "pool1",
              lifetime: 0,
              running: "00h 00m ..s",
              time_remaining: "00h ..m ..s",
              state: "running",
              ip: ""
          }
        }
        expect(last_response.body).to match(JSON.pretty_generate(expected))
      end
    end

    describe 'POST /vm' do
      it 'returns a single VM' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'returns a single VM for an alias' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'

        post "#{prefix}/vm", '{"poolone":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistant pools' do
        post "#{prefix}/vm", '{"poolpoolpool":"1"}'
        expect_json(ok = false, http = 404)
      end

      it 'returns 503 for empty pool when aliases are not defined' do
        Vmpooler::API.settings.config.delete(:alias)
        Vmpooler::API.settings.config[:pool_names] = ['pool1', 'pool2']

        create_ready_vm 'pool1', 'abcdefghijklmnop'
        post "#{prefix}/vm/pool1"
        post "#{prefix}/vm/pool1"

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns 503 for empty pool referenced by alias' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'
        post "#{prefix}/vm/poolone"
        post "#{prefix}/vm/poolone"

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns multiple VMs' do
        create_ready_vm 'pool1', 'abcdefghijklmnop'
        create_ready_vm 'pool2', 'qrstuvwxyz012345'

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'
        expect_json(ok = true, http = 200)

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          },
          pool2: {
            hostname: 'qrstuvwxyz012345'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'returns multiple VMs even when multiple instances from the same pool are requested' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'
        create_ready_vm 'pool1', '2abcdefghijklmnop'
        create_ready_vm 'pool2', 'qrstuvwxyz012345'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = {
          ok: true,
          pool1: {
            hostname: [ '1abcdefghijklmnop', '2abcdefghijklmnop' ]
          },
          pool2: {
            hostname: 'qrstuvwxyz012345'
          }
        }

        result = JSON.parse(last_response.body)
        expect(result['ok']).to eq(true)
        expect(result['pool1']['hostname']).to include('1abcdefghijklmnop', '2abcdefghijklmnop')
        expect(result['pool2']['hostname']).to eq('qrstuvwxyz012345')

        expect_json(ok = true, http = 200)
      end

      it 'returns multiple VMs even when multiple instances from multiple pools are requested' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'
        create_ready_vm 'pool1', '2abcdefghijklmnop'
        create_ready_vm 'pool2', '1qrstuvwxyz012345'
        create_ready_vm 'pool2', '2qrstuvwxyz012345'
        create_ready_vm 'pool2', '3qrstuvwxyz012345'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = {
          ok: true,
          pool1: {
            hostname: [ '1abcdefghijklmnop', '2abcdefghijklmnop' ]
          },
          pool2: {
            hostname: [ '1qrstuvwxyz012345', '2qrstuvwxyz012345', '3qrstuvwxyz012345' ]
          }
        }

        result = JSON.parse(last_response.body)
        expect(result['ok']).to eq(true)
        expect(result['pool1']['hostname']).to include('1abcdefghijklmnop', '2abcdefghijklmnop')
        expect(result['pool2']['hostname']).to include('1qrstuvwxyz012345', '2qrstuvwxyz012345', '3qrstuvwxyz012345')

        expect_json(ok = true, http = 200)
      end

      it 'fails when not all requested vms can be allocated' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', '1abcdefghijklmnop')).to eq(true)
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', '1abcdefghijklmnop')).to eq(true)
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        create_ready_vm 'pool1', '1abcdefghijklmnop'
        create_ready_vm 'pool1', '2abcdefghijklmnop'

        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', '1abcdefghijklmnop')).to eq(true)
        expect(pool_has_ready_vm?('pool1', '2abcdefghijklmnop')).to eq(true)
      end

      context '(auth not configured)' do
        it 'does not extend VM lifetime if auth token is provided' do
          app.settings.set :config, auth: false

          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime']).to be_nil
        end
      end

      context '(auth configured)' do
        it 'extends VM lifetime if auth token is provided' do
          app.settings.set :config, auth: true

          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime'].to_i).to eq(2)
        end

        it 'does not extend VM lifetime if auth token is not provided' do
          app.settings.set :config, auth: true
          create_ready_vm 'pool1', 'abcdefghijklmnop'

          post "#{prefix}/vm", '{"pool1":"1"}'
          expect_json(ok = true, http = 200)

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime']).to be_nil
        end
      end
    end
  end
end
