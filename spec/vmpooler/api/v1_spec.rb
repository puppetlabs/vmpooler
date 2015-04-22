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

  describe '/token' do
    let(:redis)  { double('redis') }
    let(:prefix) { '/api/v1' }

    before do
      app.settings.set :config, config
      app.settings.set :redis, redis
    end

    describe 'GET /token/:token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          get "#{prefix}/token/this"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(404)
        end
      end

      context '(auth configured)' do
        before do
          allow(redis).to receive(:hgetall).and_return 'atoken'
        end

        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          get "#{prefix}/token/this"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(401)
        end

        it 'returns a token if authed' do
          authorize 'admin', 's3cr3t'

          get "#{prefix}/token/this"

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true, 'this' => 'atoken'}))
          expect(last_response.status).to eq(200)
        end
      end
    end

    describe 'POST /token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          post "#{prefix}/token"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(404)
        end
      end

      context '(auth configured)' do
        before do
          allow(redis).to receive(:hset).and_return '1'
        end

        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          post "#{prefix}/token"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(401)
        end

        it 'returns a token if authed' do
          authorize 'admin', 's3cr3t'

          post "#{prefix}/token"

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(JSON.parse(last_response.body)['ok']).to eq(true)
          expect(JSON.parse(last_response.body)['token'].length).to be(32)
          expect(last_response.status).to eq(200)
        end
      end
    end

    describe 'DELETE /token/:token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          delete "#{prefix}/token/this"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(404)
        end
      end

      context '(auth configured)' do
        before do
          allow(redis).to receive(:del).and_return '1'
        end

        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          delete "#{prefix}/token/this"

          expect(last_response).not_to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(401)
        end

        it 'deletes a token if authed' do
          authorize 'admin', 's3cr3t'

          delete "#{prefix}/token/this"

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end
      end
    end

  end

end
