require 'spec_helper'
require 'rack/test'

def has_set_tag?(vm, tag, value)
  value == redis.hget("vmpooler__vm__#{vm}", "tag:#{tag}")
end

describe Vmpooler::API::V1 do
  include Rack::Test::Methods

  def app()
    Vmpooler::API
  end

  describe '/vm/:hostname' do
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
        auth: false
      }
    }

    let(:current_time) { Time.now }

    let(:redis) { MockRedis.new }

    before(:each) do
      app.settings.set :config, config
      app.settings.set :redis, redis
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'PUT /vm/:hostname' do
      it 'allows tags to be set' do
        create_vm('testhost', redis)
        put "#{prefix}/vm/testhost", '{"tags":{"tested_by":"rspec"}}'
        expect_json(ok = true, http = 200)

        expect has_set_tag?('testhost', 'tested_by', 'rspec')
      end

      it 'skips empty tags' do
        create_vm('testhost', redis)
        put "#{prefix}/vm/testhost", '{"tags":{"tested_by":""}}'
        expect_json(ok = true, http = 200)

        expect !has_set_tag?('testhost', 'tested_by', '')
      end

      it 'does not set tags if request body format is invalid' do
        create_vm('testhost', redis)
        put "#{prefix}/vm/testhost", '{"tags":{"tested"}}'
        expect_json(ok = false, http = 400)

        expect !has_set_tag?('testhost', 'tested', '')
      end

      context '(allowed_tags configured)' do
        it 'fails if specified tag is not in allowed_tags array' do
          app.settings.set :config,
             { :config => { 'allowed_tags' => ['created_by', 'project', 'url'] } }

          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"tags":{"created_by":"rspec","tested_by":"rspec"}}'
          expect_json(ok = false, http = 400)

          expect !has_set_tag?('testhost', 'tested_by', 'rspec')
        end
      end

      context '(tagfilter configured)' do
        let(:config) { {
          tagfilter: { 'url' => '(.*)\/' },
        } }

        it 'correctly filters tags' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com/something.html"}}'
          expect_json(ok = true, http = 200)

          expect has_set_tag?('testhost', 'url', 'foo.com')
        end

        it "doesn't eat tags not matching filter" do
          create_vm('testhost', redis)
          put "#{prefix}/vm/testhost", '{"tags":{"url":"foo.com"}}'
          expect_json(ok = true, http = 200)

          expect has_set_tag?('testhost', 'url', 'foo.com')
        end
      end

      context '(auth not configured)' do
        let(:config) { { auth: false } }

        it 'allows VM lifetime to be modified without a token' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'
          expect_json(ok = true, http = 200)

          vm = fetch_vm('testhost')
          expect(vm['lifetime'].to_i).to eq(1)
        end

        it 'does not allow a lifetime to be 0' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"0"}'
          expect_json(ok = false, http = 400)

          vm = fetch_vm('testhost')
          expect(vm['lifetime']).to be_nil
        end

        it 'does not enforce a lifetime' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"20000"}'
          expect_json(ok = true, http = 200)

          vm = fetch_vm('testhost')
          expect(vm['lifetime']).to eq("20000")
        end

        it 'does not allow a lifetime to be initially past config max_lifetime_upper_limit' do
          app.settings.set :config,
                           { :config => { 'max_lifetime_upper_limit' => 168 } }
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"200"}'
          expect_json(ok = false, http = 400)

          vm = fetch_vm('testhost')
          expect(vm['lifetime']).to be_nil
        end

#       it 'does not allow a lifetime to be extended past config 168' do
#         app.settings.set :config,
#                          { :config => { 'max_lifetime_upper_limit' => 168 } }
#         create_vm('testhost', redis)
#
#         set_vm_data('testhost', "checkout", (Time.now - (69*60*60)), redis)
#         puts redis.hget("vmpooler__vm__testhost", 'checkout')
#         put "#{prefix}/vm/testhost", '{"lifetime":"100"}'
#         expect_json(ok = false, http = 400)
#
#         vm = fetch_vm('testhost')
#         expect(vm['lifetime']).to be_nil
#       end
      end

      context '(auth configured)' do
        before(:each) do
          app.settings.set :config, auth: true
        end

        it 'allows VM lifetime to be modified with a token' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"1"}', {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 200)

          vm = fetch_vm('testhost')
          expect(vm['lifetime'].to_i).to eq(1)
        end

        it 'does not allows VM lifetime to be modified without a token' do
          create_vm('testhost', redis)

          put "#{prefix}/vm/testhost", '{"lifetime":"1"}'
          expect_json(ok = false, http = 401)
        end
      end
    end

    describe 'DELETE /vm/:hostname' do
      context '(auth not configured)' do
        it 'does not delete a non-existant VM' do
          delete "#{prefix}/vm/testhost"
          expect_json(ok = false, http = 404)
        end

        it 'deletes an existing VM' do
          create_running_vm('pool1', 'testhost', redis)
          expect fetch_vm('testhost')

          delete "#{prefix}/vm/testhost"
          expect_json(ok = true, http = 200)
          expect !fetch_vm('testhost')
        end
      end

      context '(auth configured)' do
        before(:each) do
          app.settings.set :config, auth: true
        end

        context '(checked-out without token)' do
          it 'deletes a VM without supplying a token' do
            create_running_vm('pool1', 'testhost', redis)
            expect fetch_vm('testhost')

            delete "#{prefix}/vm/testhost"
            expect_json(ok = true, http = 200)
            expect !fetch_vm('testhost')
          end
        end

        context '(checked-out with token)' do
          it 'fails to delete a VM without supplying a token' do
            create_running_vm('pool1', 'testhost', redis, 'abcdefghijklmnopqrstuvwxyz012345')
            expect fetch_vm('testhost')

            delete "#{prefix}/vm/testhost"
            expect_json(ok = false, http = 401)
            expect fetch_vm('testhost')
          end

          it 'deletes a VM when token is supplied' do
            create_running_vm('pool1', 'testhost', redis, 'abcdefghijklmnopqrstuvwxyz012345')
            expect fetch_vm('testhost')

            delete "#{prefix}/vm/testhost", "", {
              'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
            }
            expect_json(ok = true, http = 200)

            expect !fetch_vm('testhost')
          end
        end
      end
    end

    describe 'POST /vm/:hostname/snapshot' do
      context '(auth not configured)' do
        it 'creates a snapshot' do
          create_vm('testhost', redis)
          post "#{prefix}/vm/testhost/snapshot"
          expect_json(ok = true, http = 202)
          expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)
        end
      end

      context '(auth configured)' do
        before(:each) do
          app.settings.set :config, auth: true
        end

        it 'returns a 401 if not authed' do
          post "#{prefix}/vm/testhost/snapshot"
          expect_json(ok = false, http = 401)
          expect !has_vm_snapshot?('testhost', redis)
        end

        it 'creates a snapshot if authed' do
          create_vm('testhost', redis)
          snapshot_vm('testhost', 'testsnapshot', redis)

          post "#{prefix}/vm/testhost/snapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 202)
          expect(JSON.parse(last_response.body)['testhost']['snapshot'].length).to be(32)
          expect has_vm_snapshot?('testhost', redis)
        end
      end
    end

    describe 'POST /vm/:hostname/snapshot/:snapshot' do
      context '(auth not configured)' do
        it 'reverts to a snapshot' do
          create_vm('testhost', redis)
          snapshot_vm('testhost', 'testsnapshot', redis)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot"
          expect_json(ok = true, http = 202)
          expect vm_reverted_to_snapshot?('testhost', redis, 'testsnapshot')
        end

        it 'fails if the specified snapshot does not exist' do
          create_vm('testhost', redis)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = false, http = 404)
          expect !vm_reverted_to_snapshot?('testhost', redis, 'testsnapshot')
        end
      end

      context '(auth configured)' do
        before(:each) do
          app.settings.set :config, auth: true
        end

        it 'returns a 401 if not authed' do
          create_vm('testhost', redis)
          snapshot_vm('testhost', 'testsnapshot', redis)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot"
          expect_json(ok = false, http = 401)
          expect !vm_reverted_to_snapshot?('testhost', redis, 'testsnapshot')
        end

        it 'fails if authed and the specified snapshot does not exist' do
          create_vm('testhost', redis)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = false, http = 404)
          expect !vm_reverted_to_snapshot?('testhost', redis, 'testsnapshot')
        end

        it 'reverts to a snapshot if authed' do
          create_vm('testhost', redis)
          snapshot_vm('testhost', 'testsnapshot', redis)

          post "#{prefix}/vm/testhost/snapshot/testsnapshot", "", {
            'HTTP_X_AUTH_TOKEN' => 'abcdefghijklmnopqrstuvwxyz012345'
          }
          expect_json(ok = true, http = 202)
          expect vm_reverted_to_snapshot?('testhost', redis, 'testsnapshot')
        end
      end
    end
  end
end
