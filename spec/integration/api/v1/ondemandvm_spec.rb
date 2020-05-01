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
          'vm_lifetime_auth' => 2
        },
        pools: [
          {'name' => 'pool1', 'size' => 0},
          {'name' => 'pool2', 'size' => 0},
          {'name' => 'pool3', 'size' => 0}
        ],
        alias: { 'poolone' => ['pool1'] },
        pool_names: [ 'pool1', 'pool2', 'pool3', 'poolone', 'genericpool' ]
      }
    }
    let(:current_time) { Time.now }
    let(:vmname) { 'abcdefghijkl' }
    let(:checkoutlock) { Mutex.new }

    before(:each) do
      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :metrics, metrics
      app.settings.set :config, auth: false
      app.settings.set :checkoutlock, checkoutlock
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /ondemandvm' do
      let(:uuid) { SecureRandom.uuid }

      context 'with a configured pool' do
        it 'generates a request_id when none is provided' do
          expect(SecureRandom).to receive(:uuid).and_return(uuid)
          post "#{prefix}/ondemandvm", '{"pool1":"1"}'
          expect_json(ok = true, http = 201)

          expected = {
            "ok": true,
            "request_id": uuid
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

        it 'uses the given request_id when provided' do
          post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
          expect_json(ok = true, http = 201)

          expected = {
            "ok": true,
            "request_id": "1234"
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end

        it 'returns 404 when the request_id has been used' do
          post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
          post "#{prefix}/ondemandvm", '{"pool1":"1","request_id":"1234"}'
          expect_json(ok = false, http = 409)

          expected = {
            "ok": false,
            "request_id": "1234",
            "message": "request_id '1234' has already been created"
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end

      context 'with a pool that is not configured' do
        let(:badpool) { 'pool4' }
        it 'returns the bad template' do
          post "#{prefix}/ondemandvm", '{"pool4":"1"}'
          expect_json(ok = false, http = 404)

          expected = {
            "ok": false,
            "bad_templates": [ badpool ]
          }
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
        end
      end
    end
  end
end
