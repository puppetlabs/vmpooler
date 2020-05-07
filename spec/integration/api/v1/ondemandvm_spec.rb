require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API end

  describe '/ondemandvm' do
    let(:prefix) { '/api/v1' }
    let(:metrics) { Vmpooler::DummyStatsd.new }
    let(:config) {
      {
        config: {
          'site_name' => 'test pooler',
          'vm_lifetime_auth' => 2,
          'backend_weight' => {
            'compute1' => 5
          }
        },
        pools: [
          {'name' => 'pool1', 'size' => 0},
          {'name' => 'pool2', 'size' => 0, 'clone_target' => 'compute1'},
          {'name' => 'pool3', 'size' => 0, 'clone_target' => 'compute1'}
        ],
        alias: { 'poolone' => ['pool1'] },
        pool_names: [ 'pool1', 'pool2', 'pool3', 'poolone' ]
      }
    }
    let(:current_time) { Time.now }
    let(:vmname) { 'abcdefghijkl' }
    let(:checkoutlock) { Mutex.new }
    let(:redis) { MockRedis.new }
    let(:uuid) { SecureRandom.uuid }

    before(:each) do
      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :metrics, metrics
      app.settings.set :config, auth: false
      app.settings.set :checkoutlock, checkoutlock
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
      config[:pools].each do |pool|
        redis.sadd('vmpooler__pools', pool['name'])
      end
    end

    describe 'POST /ondemandvm' do

      context 'with a configured pool' do
        it 'generates a request_id when none is provided' do
          expect(SecureRandom).to receive(:uuid).and_return(uuid)
          post "#{prefix}/ondemandvm", '{"pool1":"1"}'
          expect_json(true, 201)

          expected = {
            "ok": true,
            "request_id": uuid
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

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

        it 'uses a configured platform to fulfill a ondemand request' do
          expect(SecureRandom).to receive(:uuid).and_return(uuid)
          post "#{prefix}/ondemandvm", '{"poolone":"1"}'
          expect_json(true, 201)
          expected = {
            "ok": true,
            "request_id": uuid
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

        it 'creates a provisioning request in redis' do
          expect(SecureRandom).to receive(:uuid).and_return(uuid)
          expect(redis).to receive(:zadd).with('vmpooler__provisioning__request', Integer, uuid).and_return(1)
          post "#{prefix}/ondemandvm", '{"poolone":"1"}'
        end

        it 'sets a platform string in redis for the request to indicate selected platforms' do
          expect(SecureRandom).to receive(:uuid).and_return(uuid)
          expect(redis).to receive(:hset).with("vmpooler__odrequest__#{uuid}", 'requested', 'poolone:pool1:1')
          post "#{prefix}/ondemandvm", '{"poolone":"1"}'
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
            set_ondemand_request_ready(uuid, redis)
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
        end
      end
    end
  end
end
