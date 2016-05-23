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

    describe 'GET /token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          get "#{prefix}/token"

          expect_json(ok = false, http = 404)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          get "#{prefix}/token"

          expect_json(ok = false, http = 401)
        end

        it 'returns a list of tokens if authed' do
          expect(redis).to receive(:keys).with('vmpooler__token__*').and_return(["vmpooler__token__abc"])
          expect(redis).to receive(:hgetall).with('vmpooler__token__abc').and_return({"user" => "admin", "created" => "now"})

          authorize 'admin', 's3cr3t'

          get "#{prefix}/token"

          expect(JSON.parse(last_response.body)['abc']['created']).to eq('now')

          expect_json(ok = true, http = 200)
        end
      end
    end

    describe 'POST /token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          post "#{prefix}/token"

          expect_json(ok = false, http = 404)
        end
      end

      context '(auth configured)' do
        before do
          allow(redis).to receive(:hset).and_return '1'
        end

        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          post "#{prefix}/token"

          expect_json(ok = false, http = 401)
        end

        it 'returns a token if authed' do
          authorize 'admin', 's3cr3t'

          post "#{prefix}/token"

          expect(JSON.parse(last_response.body)['token'].length).to be(32)

          expect_json(ok = true, http = 200)
        end
      end
    end
  end

  describe '/token/:token' do
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

          expect_json(ok = false, http = 404)
        end
      end

      context '(auth configured)' do
        let(:config) { {
          auth: true,
          pools: [
            {'name' => 'pool1', 'size' => 5}
          ]
        } }

        it 'returns a token' do
          expect(redis).to receive(:hgetall).with('vmpooler__token__this').and_return({'user' => 'admin'})
          expect(redis).to receive(:smembers).with('vmpooler__running__pool1').and_return(['vmhostname'])
          expect(redis).to receive(:hget).with('vmpooler__vm__vmhostname', 'token:token').and_return('this')

          get "#{prefix}/token/this"

          expect(JSON.parse(last_response.body)['ok']).to eq(true)
          expect(JSON.parse(last_response.body)['this']['user']).to eq('admin')
          expect(JSON.parse(last_response.body)['this']['vms']['running']).to include('vmhostname')

          expect_json(ok = true, http = 200)
        end
      end
    end

    describe 'DELETE /token/:token' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'returns a 404' do
          delete "#{prefix}/token/this"

          expect_json(ok = false, http = 404)
        end
      end

      context '(auth configured)' do
        before do
          allow(redis).to receive(:del).and_return '1'
        end

        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          delete "#{prefix}/token/this"

          expect_json(ok = false, http = 401)
        end

        it 'deletes a token if authed' do
          authorize 'admin', 's3cr3t'

          delete "#{prefix}/token/this"

          expect_json(ok = true, http = 200)
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
      ],
      alias: { 'poolone' => 'pool1' }
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
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'returns a single VM for an alias' do
        expect(redis).to receive(:exists).with("vmpooler__ready__poolone").and_return(false)

        post "#{prefix}/vm", '{"poolone":"1"}'

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'fails on nonexistant pools' do
        expect(redis).to receive(:exists).with("vmpooler__ready__poolpoolpool").and_return(false)

        post "#{prefix}/vm", '{"poolpoolpool":"1"}'

        expect_json(ok = false, http = 404)
      end

      it 'returns multiple VMs' do
        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

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

        expect_json(ok = true, http = 200)
      end

      it 'returns multiple VMs even when multiple instances from the same pool are requested' do
        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = {
          ok: true,
          pool1: {
            hostname: [ 'abcdefghijklmnop', 'abcdefghijklmnop' ]
          },
          pool2: {
            hostname: 'qrstuvwxyz012345'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'returns multiple VMs even when multiple instances from multiple pools are requested' do
        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = {
          ok: true,
          pool1: {
            hostname: [ 'abcdefghijklmnop', 'abcdefghijklmnop' ]
          },
          pool2: {
            hostname: [ 'qrstuvwxyz012345', 'qrstuvwxyz012345', 'qrstuvwxyz012345' ]
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'fails when not all requested vms can be allocated' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        allow(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop")

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        expect(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop")

        post "#{prefix}/vm", '{"pool1":"1","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        allow(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop")

        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from a pool' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        expect(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop").exactly(2).times

        post "#{prefix}/vm", '{"pool1":"2","pool2":"1"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
      end

      it 'fails when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        allow(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop")

        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
      end

      it 'returns any checked out vms to their pools when not all requested vms can be allocated, when requesting multiple instances from multiple pools' do
        allow(redis).to receive(:spop).with('vmpooler__ready__pool1').and_return 'abcdefghijklmnop'
        allow(redis).to receive(:spop).with('vmpooler__ready__pool2').and_return nil
        expect(redis).to receive(:spush).with("vmpooler__ready__pool1", "abcdefghijklmnop").exactly(2).times

        post "#{prefix}/vm", '{"pool1":"2","pool2":"3"}'

        expected = { ok: false }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))
        expect_json(ok = false, http = 200) # which HTTP status code?
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
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
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
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
        end

        it 'does not extend VM lifetime if auth token is not provided' do
          expect(redis).not_to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2)

          post "#{prefix}/vm", '{"pool1":"1"}'

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
        end
      end
    end
  end

  describe '/vm/:template' do
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
      ],
      alias: { 'poolone' => 'pool1' }
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

    describe 'POST /vm/:template' do
      it 'returns a single VM' do
        post "#{prefix}/vm/pool1", ''

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'returns a single VM for an alias' do
        expect(redis).to receive(:exists).with("vmpooler__ready__poolone").and_return(false)

        post "#{prefix}/vm/poolone", ''

        expected = {
          ok: true,
          pool1: {
            hostname: 'abcdefghijklmnop'
          }
        }

        expect(last_response.body).to eq(JSON.pretty_generate(expected))

        expect_json(ok = true, http = 200)
      end

      it 'fails on nonexistant pools' do
        expect(redis).to receive(:exists).with("vmpooler__ready__poolpoolpool").and_return(false)

        post "#{prefix}/vm/poolpoolpool", ''

        expect_json(ok = false, http = 404)
      end

      it 'returns multiple VMs' do
        post "#{prefix}/vm/pool1+pool2", ''

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

        expect_json(ok = true, http = 200)
      end

      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'does not extend VM lifetime if auth token is provided' do
          expect(redis).not_to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2)

          post "#{prefix}/vm/pool1", '', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'extends VM lifetime if auth token is provided' do
          expect(redis).to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2).once

          post "#{prefix}/vm/pool1", '', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
        end

        it 'does not extend VM lifetime if auth token is not provided' do
          expect(redis).not_to receive(:hset).with("vmpooler__vm__abcdefghijklmnop", "lifetime", 2)

          post "#{prefix}/vm/pool1", ''

          expected = {
            ok: true,
            pool1: {
              hostname: 'abcdefghijklmnop'
            }
          }

          expect(last_response.body).to eq(JSON.pretty_generate(expected))

          expect_json(ok = true, http = 200)
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

          expect_json(ok = true, http = 200)
        end

        it 'skips empty tags' do
          put "#{prefix}/vm/testhost", '{"tags":{"tested_by":""}}'

          expect_json(ok = true, http = 200)
        end

        it 'does not set tags if request body format is invalid' do
          put "#{prefix}/vm/testhost", '{"tags":{"tested"}}'

          expect_json(ok = false, http = 400)
        end

      context '(allowed_tags configured)' do
        let(:config) { {
          config: {
            'allowed_tags' => ['created_by', 'project', 'url']
          }
        } }

        it 'fails if specified tag is not in allowed_tags array' do
          put "#{prefix}/vm/testhost", '{"tags":{"created_by":"rspec","tested_by":"rspec"}}'

          expect_json(ok = false, http = 400)
        end
      end

      context '(tagfilter configured)' do
        let(:config) { {
          tagfilter: { 'url' => '(.*)\/' },
        } }

        it 'correctly filters tags' do
          expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")

          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com/something.html"}}'

          expect_json(ok = true, http = 200)
        end

        it 'doesn\'t eat tags not matching filter' do
          expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")

          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com"}}'

          expect_json(ok = true, http = 200)
        end
      end

      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'allows VM lifetime to be modified without a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'

          expect_json(ok = true, http = 200)
        end

        it 'does not allow a lifetime to be 0' do
          put "#{prefix}/vm/testhost", '{"lifetime":"0"}'

          expect_json(ok = false, http = 400)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'allows VM lifetime to be modified with a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expect_json(ok = true, http = 200)
        end

        it 'does not allows VM lifetime to be modified without a token' do
          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'

          expect_json(ok = false, http = 401)
        end
      end
    end

    describe 'DELETE /vm/:hostname' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'does not delete a non-existant VM' do
          expect(redis).to receive(:hgetall).and_return({})
          expect(redis).not_to receive(:sadd)
          expect(redis).not_to receive(:srem)

          delete "#{prefix}/vm/testhost"

          expect_json(ok = false, http = 404)
        end

        it 'deletes an existing VM' do
          expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1"})
          expect(redis).to receive(:srem).and_return(true)
          expect(redis).to receive(:sadd)

          delete "#{prefix}/vm/testhost"

          expect_json(ok = true, http = 200)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        context '(checked-out without token)' do
          it 'deletes a VM without supplying a token' do
            expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1"})
            expect(redis).to receive(:srem).and_return(true)
            expect(redis).to receive(:sadd)

            delete "#{prefix}/vm/testhost"

            expect_json(ok = true, http = 200)
          end
        end

        context '(checked-out with token)' do
          it 'fails to delete a VM without supplying a token' do
            expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1", "token:token" => "abcdefghijklmnopqrstuvwxyz012345"})
            expect(redis).not_to receive(:sadd)
            expect(redis).not_to receive(:srem)

            delete "#{prefix}/vm/testhost"

            expect_json(ok = false, http = 401)
          end

          it 'deletes a VM when token is supplied' do
            expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1", "token:token" => "abcdefghijklmnopqrstuvwxyz012345"})
            expect(redis).to receive(:srem).and_return(true)
            expect(redis).to receive(:sadd)

            delete "#{prefix}/vm/testhost", "", {
              'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
            }

            expect_json(ok = true, http = 200)
          end
        end
      end
    end

    describe 'POST /vm/:hostname/snapshot' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'creates a snapshot' do
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot"

          expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)

          expect_json(ok = true, http = 202)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          post "#{prefix}/vm/testhost/snapshot"

          expect_json(ok = false, http = 401)
        end

        it 'creates a snapshot if authed' do
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)

          expect_json(ok = true, http = 202)
        end
      end
    end

    describe 'POST /vm/:hostname/snapshot/:snapshot' do
      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'reverts to a snapshot' do
          expect(redis).to receive(:hget).with('vmpooler__vm__testhost', 'snapshot:testsnapshot').and_return(1)
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot"

          expect_json(ok = true, http = 202)
        end
      end

      context '(auth configured)' do
        let(:config) { { auth: true } }

        it 'returns a 401 if not authed' do
          post "#{prefix}/vm/testhost/snapshot"

          expect_json(ok = false, http = 401)
        end

        it 'reverts to a snapshot if authed' do
          expect(redis).to receive(:hget).with('vmpooler__vm__testhost', 'snapshot:testsnapshot').and_return(1)
          expect(redis).to receive(:sadd)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }

          expect_json(ok = true, http = 202)
        end
      end

    end
  end

end
