require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    # because of how Vmpooler::API.settings are used
    # we need to test the whole thing...
    Vmpooler::API
  end

  describe 'tokens' do
    let(:redis) { double('redis') }
    let(:config) {
      {
          config: {'site_name' => 'test pooler'},
          auth:   {exists: 1}
      }
    }
    let(:prefix) { '/api/v1' }

    before do
      $config = config

      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :environment, :test
    end

    describe 'GET /token/:token' do

      context 'valid tokens' do
        before do
          allow(redis).to receive(:exists).and_return 1
          allow(redis).to receive(:hgetall).and_return 'atoken'
        end

        it 'sets key to passed value (:token)' do
          get "#{prefix}/token/this"

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true, 'this' => 'atoken'}))
          expect(last_response.header['Content-Type']).to eq('application/json')

          get "#{prefix}/token/that"

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true, 'that' => 'atoken'}))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end
      end

    end

    describe 'DELETE /token/:token' do

      context 'valid tokens' do
        before do
          allow(redis).to receive(:exists).with(String).and_return 1
          allow(redis).to receive(:del)
        end

        it 'deletes the key' do
          expect(redis).to receive(:del)

          delete "#{prefix}/token/this"

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
        end
      end
    end

  end

end