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

def redis
  @redis ||= Redis.new
end

def create_token(token, user, timestamp)
  redis.hset("vmpooler__token__#{token}", 'user', user)
  redis.hset("vmpooler__token__#{token}", 'created', timestamp)
end

def create_vm(template, name)
  redis.sadd('vmpooler__ready__' + template, name)
end

def fetch_vm(vm)
  redis.hgetall("vmpooler__vm__#{vm}")
end

def clear_pool(pool)
  ['ready'].each do |state| # TODO add more states if desired
    redis.del("vmpooler__#{state}__#{pool}")
  end
end

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  describe '/vm' do
    let(:prefix) { '/api/v1' }

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
        alias: { 'poolone' => 'pool1' },
      }
    }

    let(:current_time) { Time.now }

    before(:each) do
      redis.flushdb

      app.settings.set :config, config
      app.settings.set :redis, redis
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'POST /vm' do
      it 'returns a single VM' do
        clear_pool 'pool1'
        create_vm 'pool1', 'abcdefghijklmnop'

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
        clear_pool 'pool1'
        create_vm 'pool1', 'abcdefghijklmnop'

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
        clear_pool 'poolpoolpool'

        post "#{prefix}/vm", '{"poolpoolpool":"1"}'
        expect_json(ok = false, http = 404)
      end

      it 'returns multiple VMs' do
        clear_pool 'pool1'
        create_vm 'pool1', 'abcdefghijklmnop'
        create_vm 'pool2', 'qrstuvwxyz012345'

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

      context '(auth not configured)' do
        it 'does not extend VM lifetime if auth token is provided' do
          app.settings.set :config, auth: false

          clear_pool 'pool1'
          create_vm 'pool1', 'abcdefghijklmnop'

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

          clear_pool 'pool1'
          create_vm 'pool1', 'abcdefghijklmnop'

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
          clear_pool 'pool1'
          create_vm 'pool1', 'abcdefghijklmnop'

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

  # describe '/vm/:hostname' do
  #   let(:redis)  { double('redis') }
  #   let(:prefix) { '/api/v1' }
  #   let(:config) { {
  #     pools: [
  #       {'name' => 'pool1', 'size' => 5},
  #       {'name' => 'pool2', 'size' => 10}
  #     ]
  #   } }
  #
  #   before do
  #     app.settings.set :config, config
  #     app.settings.set :redis, redis
  #
  #     allow(redis).to receive(:exists).and_return '1'
  #     allow(redis).to receive(:hset).and_return '1'
  #   end
  #
  #   describe 'PUT /vm/:hostname' do
  #       it 'allows tags to be set' do
  #         put "#{prefix}/vm/testhost", '{"tags":{"tested_by":"rspec"}}'
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #
  #       it 'skips empty tags' do
  #         put "#{prefix}/vm/testhost", '{"tags":{"tested_by":""}}'
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #
  #       it 'does not set tags if request body format is invalid' do
  #         put "#{prefix}/vm/testhost", '{"tags":{"tested"}}'
  #
  #         expect_json(ok = false, http = 400)
  #       end
  #
  #     context '(allowed_tags configured)' do
  #       let(:config) { {
  #         config: {
  #           'allowed_tags' => ['created_by', 'project', 'url']
  #         }
  #       } }
  #
  #       it 'fails if specified tag is not in allowed_tags array' do
  #         put "#{prefix}/vm/testhost", '{"tags":{"created_by":"rspec","tested_by":"rspec"}}'
  #
  #         expect_json(ok = false, http = 400)
  #       end
  #     end
  #
  #     context '(tagfilter configured)' do
  #       let(:config) { {
  #         tagfilter: { 'url' => '(.*)\/' },
  #       } }
  #
  #       it 'correctly filters tags' do
  #         expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")
  #
  #         put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com/something.html"}}'
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #
  #       it 'doesn\'t eat tags not matching filter' do
  #         expect(redis).to receive(:hset).with("vmpooler__vm__testhost", "tag:url", "foo.com")
  #
  #         put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com"}}'
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #     end
  #
  #     context '(auth not configured)' do
  #       let(:config) { { auth: false } }
  #
  #       it 'allows VM lifetime to be modified without a token' do
  #         put "#{prefix}/vm/testhost", '{"lifetime":"1"}'
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #
  #       it 'does not allow a lifetime to be 0' do
  #         put "#{prefix}/vm/testhost", '{"lifetime":"0"}'
  #
  #         expect_json(ok = false, http = 400)
  #       end
  #     end
  #
  #     context '(auth configured)' do
  #       let(:config) { { auth: true } }
  #
  #       it 'allows VM lifetime to be modified with a token' do
  #         put "#{prefix}/vm/testhost", '{"lifetime":"1"}', {
  #           'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
  #         }
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #
  #       it 'does not allows VM lifetime to be modified without a token' do
  #         put "#{prefix}/vm/testhost", '{"lifetime":"1"}'
  #
  #         expect_json(ok = false, http = 401)
  #       end
  #     end
  #   end
  #
  #   describe 'DELETE /vm/:hostname' do
  #     context '(auth not configured)' do
  #       let(:config) { { auth: false } }
  #
  #       it 'does not delete a non-existant VM' do
  #         expect(redis).to receive(:hgetall).and_return({})
  #         expect(redis).not_to receive(:sadd)
  #         expect(redis).not_to receive(:srem)
  #
  #         delete "#{prefix}/vm/testhost"
  #
  #         expect_json(ok = false, http = 404)
  #       end
  #
  #       it 'deletes an existing VM' do
  #         expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1"})
  #         expect(redis).to receive(:srem).and_return(true)
  #         expect(redis).to receive(:sadd)
  #
  #         delete "#{prefix}/vm/testhost"
  #
  #         expect_json(ok = true, http = 200)
  #       end
  #     end
  #
  #     context '(auth configured)' do
  #       let(:config) { { auth: true } }
  #
  #       context '(checked-out without token)' do
  #         it 'deletes a VM without supplying a token' do
  #           expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1"})
  #           expect(redis).to receive(:srem).and_return(true)
  #           expect(redis).to receive(:sadd)
  #
  #           delete "#{prefix}/vm/testhost"
  #
  #           expect_json(ok = true, http = 200)
  #         end
  #       end
  #
  #       context '(checked-out with token)' do
  #         it 'fails to delete a VM without supplying a token' do
  #           expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1", "token:token" => "abcdefghijklmnopqrstuvwxyz012345"})
  #           expect(redis).not_to receive(:sadd)
  #           expect(redis).not_to receive(:srem)
  #
  #           delete "#{prefix}/vm/testhost"
  #
  #           expect_json(ok = false, http = 401)
  #         end
  #
  #         it 'deletes a VM when token is supplied' do
  #           expect(redis).to receive(:hgetall).with('vmpooler__vm__testhost').and_return({"template" => "pool1", "token:token" => "abcdefghijklmnopqrstuvwxyz012345"})
  #           expect(redis).to receive(:srem).and_return(true)
  #           expect(redis).to receive(:sadd)
  #
  #           delete "#{prefix}/vm/testhost", "", {
  #             'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
  #           }
  #
  #           expect_json(ok = true, http = 200)
  #         end
  #       end
  #     end
  #   end
  #
  #   describe 'POST /vm/:hostname/snapshot' do
  #     context '(auth not configured)' do
  #       let(:config) { { auth: false } }
  #
  #       it 'creates a snapshot' do
  #         expect(redis).to receive(:sadd)
  #
  #         post "#{prefix}/vm/testhost/snapshot"
  #
  #         expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)
  #
  #         expect_json(ok = true, http = 202)
  #       end
  #     end
  #
  #     context '(auth configured)' do
  #       let(:config) { { auth: true } }
  #
  #       it 'returns a 401 if not authed' do
  #         post "#{prefix}/vm/testhost/snapshot"
  #
  #         expect_json(ok = false, http = 401)
  #       end
  #
  #       it 'creates a snapshot if authed' do
  #         expect(redis).to receive(:sadd)
  #
  #         post "#{prefix}/vm/testhost/snapshot", "", {
  #           'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
  #         }
  #
  #         expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)
  #
  #         expect_json(ok = true, http = 202)
  #       end
  #     end
  #   end
  #
  #   describe 'POST /vm/:hostname/snapshot/:snapshot' do
  #     context '(auth not configured)' do
  #       let(:config) { { auth: false } }
  #
  #       it 'reverts to a snapshot' do
  #         expect(redis).to receive(:hget).with('vmpooler__vm__testhost', 'snapshot:testsnapshot').and_return(1)
  #         expect(redis).to receive(:sadd)
  #
  #         post "#{prefix}/vm/testhost/snapshot/testsnapshot"
  #
  #         expect_json(ok = true, http = 202)
  #       end
  #     end
  #
  #     context '(auth configured)' do
  #       let(:config) { { auth: true } }
  #
  #       it 'returns a 401 if not authed' do
  #         post "#{prefix}/vm/testhost/snapshot"
  #
  #         expect_json(ok = false, http = 401)
  #       end
  #
  #       it 'reverts to a snapshot if authed' do
  #         expect(redis).to receive(:hget).with('vmpooler__vm__testhost', 'snapshot:testsnapshot').and_return(1)
  #         expect(redis).to receive(:sadd)
  #
  #         post "#{prefix}/vm/testhost/snapshot/testsnapshot", "", {
  #           'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
  #         }
  #
  #         expect_json(ok = true, http = 202)
  #       end
  #     end
  #
  #   end
  # end

end
