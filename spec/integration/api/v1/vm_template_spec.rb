require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V1 do
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

  describe '/vm/:template' do
    let(:prefix) { '/api/v1' }
    let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
        },
        pools: [
          {'name' => 'pool1', 'size' => 5},
          {'name' => 'pool2', 'size' => 10},
          {'name' => 'poolone', 'size' => 0}
        ],
        statsd: { 'prefix' => 'stats_prefix'},
        alias: { 'poolone' => 'pool1' },
        pool_names: [ 'pool1', 'pool2', 'poolone' ]
      }
    }

    let(:current_time) { Time.now }
    let(:socket) { double('socket') }
    let(:checkoutlock) { Mutex.new }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, metrics, nil)
      app.settings.set :config, auth: false
      app.settings.set :checkoutlock, checkoutlock
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /vm/:template' do
      it 'returns a single VM' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1", ''
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
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/poolone", ''

        expected = {
          ok: true,
          poolone: {
            hostname: 'abcdefghijklmnop'
          }
        }
        expect_json(ok = true, http = 200)

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      it 'fails on nonexistant pools' do
        post "#{prefix}/vm/poolpoolpool", ''
        expect_json(ok = false, http = 404)
      end

      it 'returns 503 for empty pool when aliases are not defined' do
        app.settings.config.delete(:alias)
        app.settings.config[:pool_names] = ['pool1', 'pool2']

        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        post "#{prefix}/vm/pool1"
        post "#{prefix}/vm/pool1"

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns 503 for empty pool referenced by alias' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        post "#{prefix}/vm/poolone"

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns multiple VMs' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        create_ready_vm 'pool2', 'qrstuvwxyz012345', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1+pool2", ''
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

      it 'returns multiple VMs even when multiple instances from multiple pools are requested' do
        create_ready_vm 'pool1', '1abcdefghijklmnop', redis
        create_ready_vm 'pool1', '2abcdefghijklmnop', redis

        create_ready_vm 'pool2', '1qrstuvwxyz012345', redis
        create_ready_vm 'pool2', '2qrstuvwxyz012345', redis
        create_ready_vm 'pool2', '3qrstuvwxyz012345', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1+pool1+pool2+pool2+pool2", ''

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
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis

        post "#{prefix}/vm/pool1+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', 'abcdefghijklmnop', redis)).to eq(true)
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        create_ready_vm 'pool1', '0123456789012345', redis

        post "#{prefix}/vm/pool1+pool1+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        create_ready_vm 'pool1', '0123456789012345', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1+pool1+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', 'abcdefghijklmnop', redis)).to eq(true)
        expect(pool_has_ready_vm?('pool1', '0123456789012345', redis)).to eq(true)
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        create_ready_vm 'pool2', '0123456789012345', redis

        post "#{prefix}/vm/pool1+pool1+pool2+pool2+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        create_ready_vm 'pool1', 'abcdefghijklmnop', redis
        create_ready_vm 'pool2', '0123456789012345', redis

        allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

        post "#{prefix}/vm/pool1+pool1+pool2+pool2+pool2", ''

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 503)

        expect(pool_has_ready_vm?('pool1', 'abcdefghijklmnop', redis)).to eq(true)
        expect(pool_has_ready_vm?('pool2', '0123456789012345', redis)).to eq(true)
      end

      context '(auth not configured)' do
        it 'does not extend VM lifetime if auth token is provided' do
          app.settings.set :config, auth: false

          create_ready_vm 'pool1', 'abcdefghijklmnop', redis

          allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

          post "#{prefix}/vm/pool1", '', {
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

          create_ready_vm 'pool1', 'abcdefghijklmnop', redis

          allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

          post "#{prefix}/vm/pool1", '', {
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
          create_ready_vm 'pool1', 'abcdefghijklmnop', redis

          allow_any_instance_of(Vmpooler::API::Helpers).to receive(:open_socket).and_return(socket)

          post "#{prefix}/vm/pool1", ''

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }
          expect_json(ok = true, http = 200)

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          vm = fetch_vm('abcdefghijklmnop')
          expect(vm['lifetime']).to be_nil
        end
      end
    end
  end
end
