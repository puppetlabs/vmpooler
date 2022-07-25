require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V2 do
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

  describe '/ondemandvm' do
    let(:prefix) { '/api/v2' }
    let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
          'max_ondemand_instances_per_request' => 50,
          'backend_weight' => {
            'compute1' => 5,
            'compute2' => 0
          }
        },
        pools: [
          {'name' => 'pool1', 'size' => 0, 'clone_target' => 'compute1'},
          {'name' => 'pool2', 'size' => 0, 'clone_target' => 'compute2'},
          {'name' => 'pool3', 'size' => 0, 'clone_target' => 'compute1'}
        ],
        alias: {
          'poolone' => ['pool1'],
          'pool2' => ['pool1']
        },
        pool_names: [ 'pool1', 'pool2', 'pool3', 'poolone' ],
        providers: {
          :dummy => {
            'domain' => 'dummy.com'
          }
        }
      }
    }
    let(:current_time) { Time.now }
    let(:vmname) { 'abcdefghijkl' }
    let(:checkoutlock) { Mutex.new }
    let(:uuid) { SecureRandom.uuid }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, metrics, nil)
      app.settings.set :config, auth: false
      app.settings.set :checkoutlock, checkoutlock
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
      config[:pools].each do |pool|
        redis.sadd('vmpooler__pools', pool['name'])
      end
    end

    describe 'POST /ondemandvm' do

      context 'with a configured pool' do

        context 'with no request_id provided in payload' do
          before(:each) do
            expect(SecureRandom).to receive(:uuid).and_return(uuid)
          end

          it 'generates a request_id when none is provided' do
            post "#{prefix}/ondemandvm", '{"pool1":"1"}'
            expect_json(true, 201)

            expected = {
              "ok": true,
              "request_id": uuid
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end

          it 'uses a configured platform to fulfill a ondemand request' do
            post "#{prefix}/ondemandvm", '{"poolone":"1"}'
            expect_json(true, 201)
            expected = {
              "ok": true,
              "request_id": uuid
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end

          it 'creates a provisioning request in redis' do
            expect(redis).to receive(:zadd).with('vmpooler__provisioning__request', Integer, uuid).and_return(1)
            post "#{prefix}/ondemandvm", '{"poolone":"1"}'
          end

          it 'sets a platform string in redis for the request to indicate selected platforms' do
            expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'requested', 'poolone:pool1:1')
            post "#{prefix}/ondemandvm", '{"poolone":"1"}'
          end

          context 'with a backend of 0 weight' do
            before(:each) do
              config[:config]['backend_weight']['compute1'] = 0
            end

            it 'sets the platform string in redis for the request to indicate the selected platforms' do
              expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'requested', 'pool1:pool1:1')
              post "#{prefix}/ondemandvm", '{"pool1":"1"}'
            end
          end

          it 'sets the platform string in redis for the request to indicate the selected platforms using weight' do
            expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'requested', 'pool2:pool1:1')
            post "#{prefix}/ondemandvm", '{"pool2":"1"}'
          end

          context 'with domain set in the config' do
            let(:domain) { 'example.com' }
            before(:each) do
              config[:config]['domain'] = domain
            end

            it 'should include domain in the return reply' do
              post "#{prefix}/ondemandvm", '{"poolone":"1"}'
              expect_json(true, 201)
              expected = {
                "ok": true,
                "request_id": uuid,
              }
              expect(last_response.body).to eq(JSON.pretty_generate(expected))
            end
          end
        end

        context 'with a resource request that exceeds the specified limit' do
          let(:max_instances) { 50 }
          before(:each) do
            config[:config]['max_ondemand_instances_per_request'] = max_instances
          end

          it 'should reject the request with a message' do
            post "#{prefix}/ondemandvm", '{"pool1":"51"}'
            expect_json(false, 403)
            expected = {
              "ok": false,
              "message": "requested amount of instances exceeds the maximum #{max_instances}"
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end
        end

        context 'with request_id provided in the payload' do
          it 'uses the given request_id when provided' do
            post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
            expect_json(true, 201)

            expected = {
              "ok": true,
              "request_id": "1234"
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end

          it 'returns 409 conflict error when the request_id has been used' do
            post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
            post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
            expect_json(false, 409)

            expected = {
              "ok": false,
              "request_id": "1234",
              "message": "request_id '1234' has already been created"
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end
        end

        context 'with auth configured' do

          it 'sets the token and user' do
            app.settings.set :config, auth: true
            expect(SecureRandom).to receive(:uuid).and_return(uuid)
            allow(redis).to receive(:hset)
            expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'token:token', 'abcdefghijklmnopqrstuvwxyz012345')
            expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'token:user', 'jdoe')
            post "#{prefix}/ondemandvm", '{"pool1":"1"}', {
              'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
            }
          end
        end
      end

      context 'with a pool that is not configured' do
        let(:badpool) { 'pool4' }
        it 'returns the bad template' do
          post "#{prefix}/ondemandvm", '{"pool4":"1"}'
          expect_json(false, 404)

          expected = {
            "ok": false,
            "bad_templates": [ badpool ]
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

      it 'returns 400 and a message when JSON is invalid' do
        post "#{prefix}/ondemandvm", '{"pool1":"1}'
        expect_json(false, 400)
        expected = {
          "ok": false,
          "message": "JSON payload could not be parsed"
        }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end
    end

    describe 'GET /ondemandvm' do
      it 'returns 404 with message when request is not found' do
        get "#{prefix}/ondemandvm/#{uuid}"
        expect_json(false, 404)
        expected = {
          "ok": false,
          "message": "no request found for request_id '#{uuid}'"
        }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'when the request is found' do
        let(:score) { current_time }
        let(:platforms_string) { 'pool1:pool1:1' }
        before(:each) do
          create_ondemand_request_for_test(uuid, score, platforms_string, redis)
        end

        it 'returns 202 while the request is waiting' do
          get "#{prefix}/ondemandvm/#{uuid}"
          expect_json(true, 202)
          expected = {
            "ok": true,
            "request_id": uuid,
            "ready": false,
            "pool1": {
              "ready": "0",
              "pending": "1"
            }
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

        context 'with ready instances' do
          before(:each) do
            create_ondemand_vm(vmname, uuid, 'pool1', 'pool1', redis)
            set_ondemand_request_status(uuid, 'ready', redis)
          end

          it 'returns 200 with hostnames when the request is ready' do
            get "#{prefix}/ondemandvm/#{uuid}"
            expect_json(true, 200)
            expected = {
              "ok": true,
              "request_id": uuid,
              "ready": true,
              "pool1": {
                "hostname": [
                  vmname
                ]
              }
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end

          context 'with domain set' do
            let(:domain) { 'example.com' }
            before(:each) do
              config[:config]['domain'] = domain
            end

            it 'should include the domain in the hostname as fqdn, not a separate key unlike in v1' do
              get "#{prefix}/ondemandvm/#{uuid}"
              expected = {
                "ok": true,
                "request_id": uuid,
                "ready": true,
                "pool1": {
                  "hostname": [
                    "#{vmname}.#{domain}"
                  ]
                }
              }
              expect(last_response.body).to eq(JSON.pretty_generate(expected))
            end
          end

          context 'with domain set in the provider' do
            let(:domain) { 'dummy.com' }
            before(:each) do
              config[:pools][0]['provider'] = 'dummy'
            end

            it 'should include the domain in the hostname as fqdn, not a separate key unlike in v1' do
              get "#{prefix}/ondemandvm/#{uuid}"
              expected = {
                "ok": true,
                "request_id": uuid,
                "ready": true,
                "pool1": {
                  "hostname": [
                    "#{vmname}.#{domain}"
                  ]
                }
              }
              expect(last_response.body).to eq(JSON.pretty_generate(expected))
            end
          end
        end

        context 'with a deleted request' do
          before(:each) do
            set_ondemand_request_status(uuid, 'deleted', redis)
          end

          it 'returns a message that the request has been deleted' do
            get "#{prefix}/ondemandvm/#{uuid}"
            expect_json(true, 200)
            expected = {
              "ok": true,
              "request_id": uuid,
              "ready": false,
              "message": "The request has been deleted"
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end
        end

        context 'with a failed request' do
          let(:ondemand_request_ttl) { 5 }
          before(:each) do
            config[:config]['ondemand_request_ttl'] = ondemand_request_ttl
            set_ondemand_request_status(uuid, 'failed', redis)
          end

          it 'returns a message that the request has failed' do
            get "#{prefix}/ondemandvm/#{uuid}"
            expect_json(true, 200)
            expected = {
              "ok": true,
              "request_id": uuid,
              "ready": false,
              "message": "The request failed to provision instances within the configured ondemand_request_ttl '#{ondemand_request_ttl}'"
            }
            expect(last_response.body).to eq(JSON.pretty_generate(expected))
          end
        end
      end
    end

    describe 'DELETE /ondemandvm' do
      let(:expiration) { 129_600_0 }
      it 'returns 404 with message when request is not found' do
        delete "#{prefix}/ondemandvm/#{uuid}"
        expect_json(false, 404)
        expected = {
          "ok": false,
          "message": "no request found for request_id '#{uuid}'"
        }
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
      end

      context 'when the request is found' do
        let(:platforms_string) { 'pool1:pool1:1' }
        let(:score) { current_time.to_i }
        before(:each) do
          create_ondemand_request_for_test(uuid, score, platforms_string, redis)
        end

        it 'returns 200 for a deleted request' do
          delete "#{prefix}/ondemandvm/#{uuid}"
          expect_json(true, 200)
          expected = { 'ok': true }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

        it 'marks the request hash for expiration in two weeks' do
          expect(redis).to receive(:expire).with("vmpooler__odrequest__#{uuid}", expiration)
          delete "#{prefix}/ondemandvm/#{uuid}"
        end

        context 'with running instances' do
          let(:pool) { 'pool1' }
          let(:pool_alias) { pool }
          before(:each) do
            create_ondemand_vm(vmname, uuid, pool, pool_alias, redis)
          end

          it 'moves allocated instances to the completed queue' do
            expect(redis).to receive(:smove).with("vmpooler__running__#{pool}", "vmpooler__completed__#{pool}", vmname)
            delete "#{prefix}/ondemandvm/#{uuid}"
          end

          it 'deletes the set tracking instances allocated for the request' do
            expect(redis).to receive(:del).with("vmpooler__#{uuid}__#{pool_alias}__#{pool}")
            delete "#{prefix}/ondemandvm/#{uuid}"
          end
        end
      end
    end
  end
end
