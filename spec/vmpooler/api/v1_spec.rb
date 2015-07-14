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

  describe '/vm' do
    let(:redis)  { double('redis') }
    let(:prefix) { '/api/v1' }
    let(:config) { {
      config: {
        'site_name' => 'test pooler',
        'vm_lifetime_auth' => 2
      },
      pools: [
        {'name' => 'pool1', 'size' => 5},
        {'name' => 'pool2', 'size' => 10}
      ]
    } }

    before do
      app.settings.set :config, config
      app.settings.set :redis, redis

      allow(redis).to receive(:exists).and_return '1'
      allow(redis).to receive(:hget).with('vmpooler__token__abcdefghijklmnopqrstuvwxyz012345', 'user').and_return 'jdoe'
      allow(redis).to receive(:hset).and_return '1'
      allow(redis).to receive(:sadd).and_return '1'
      allow(redis).to receive(:scard).and_return '5'
      allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
      allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return 'qrstuvwxyz012345'
    end

    describe 'POST /vm' do
      it 'returns a single VM' do
        post "#{prefix}/vm", '{"pool1":"1"}'

        expected = {
          ok: true,
          pool1: {
            ok: true,
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response).to be_ok
        expect(last_response.header['Content-Type']).to eq('application/json')
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect(last_response.status).to eq(200)
      end

      it 'returns multiple VMs' do
        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

        expected = {
          ok: true,
          pool1: {
            ok: true,
            hostname: 'abcdefghijklmnop'
          },
          pool2: {
            ok: true,
            hostname: 'qrstuvwxyz012345'
          }
        }

        expect(last_response).to be_ok
        expect(last_response.header['Content-Type']).to eq('application/json')
        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect(last_response.status).to eq(200)
      end

      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'does not extend VM lifetime if auth token is provided' do
          expect(redis).not_to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2)

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expected = {
            ok: true,
            pool1: {
              ok: true,
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
          expect(last_response.status).to eq(200)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'extends VM lifetime if auth token is provided' do
          expect(redis).to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2).once

          post "#{prefix}/vm", '{"pool1":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expected = {
            ok: true,
            pool1: {
              ok: true,
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
          expect(last_response.status).to eq(200)
        end

        it 'does not extend VM lifetime if auth token is not provided' do
          expect(redis).not_to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2)

          post "#{prefix}/vm", '{"pool1":"1"}'

          expected = {
            ok: true,
            pool1: {
              ok: true,
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate(expected))
          expect(last_response.status).to eq(200)
        end
      end
    end
  end

  describe '/vm/:hostname' do
    let(:redis)  { double('redis') }
    let(:prefix) { '/api/v1' }
    let(:config) { {
      pools: [
        {'name' => 'pool1', 'size' => 5},
        {'name' => 'pool2', 'size' => 10}
      ]
    } }

    before do
      app.settings.set :config, config
      app.settings.set :redis, redis

      allow(redis).to receive(:exists).and_return '1'
      allow(redis).to receive(:hset).and_return '1'
    end

    describe 'PUT /vm/:hostname' do
        it 'allows tags to be set' do
          put "#{prefix}/vm/testhost", '{"tags":{"tested_by":"rspec"}}'

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end

        it 'skips empty tags' do
          put "#{prefix}/vm/testhost", '{"tags":{"tested_by":""}}'

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end

        it 'does not set tags if request body format is invalid' do
          put "#{prefix}/vm/testhost", '{"tags":{"tested"}}'

          expect(last_response).to_not be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(400)
        end

      context '(allowed_tags configured)' do
        let(:config) { {
          config: {
            'allowed_tags' => ['created_by', 'project', 'url']
          }
        } }

        it 'fails if specified tag is not in allowed_tags array' do
          put "#{prefix}/vm/testhost", '{"tags":{"created_by":"rspec","tested_by":"rspec"}}'

          expect(last_response).to_not be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(400)
        end
      end

      context '(tagfilter configured)' do
        let(:config) { {
          tagfilter: { 'url' => '(.*)\/' },
        } }

        it 'correctly filters tags' do
          expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")

          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com/something.html"}}'

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end

        it 'doesn\'t eat tags not matching filter' do
          expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")

          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com"}}'

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end
      end

      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'allows VM lifetime to be modified without a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end

        it 'does not allow a lifetime to be 0' do
          put "#{prefix}/vm/testhost", '{"lifetime":"0"}'

          expect(last_response).to_not be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(400)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'allows VM lifetime to be modified with a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expect(last_response).to be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => true}))
          expect(last_response.status).to eq(200)
        end

        it 'does not allows VM lifetime to be modified without a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'

          expect(last_response).to_not be_ok
          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to eq(JSON.pretty_generate({'ok' => false}))
          expect(last_response.status).to eq(401)
        end
      end
    end

    describe 'POST /vm/:hostname/snapshot' do
        it 'creates a snapshot' do
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot"

          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(JSON.parse(last_response.body)['ok']).to eq(true)
          expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)
          expect(last_response.status).to eq(202)
        end
    end

    describe 'POST /vm/:hostname/snapshot/:snapshot' do
        it 'reverts to a snapshot' do
          expect(redis).to receive(:exists).with('vmpooler__vm__testhost').and_return(1)
          expect(redis).to receive(:hget).with('vmpooler__vm__testhost', 'snapshot:testsnapshot').and_return(1)
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot"

          expect(last_response.header['Content-Type']).to eq('application/json')
          expect(last_response.body).to include('"ok": true')
          expect(last_response.status).to eq(202)
        end
    end
  end

end
