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

  describe '/token' do
    let(:prefix) { '/api/v1' }
    let(:current_time) { Time.now }
    let(:config) { { } }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute(['api'], config, redis, nil)
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
        let(:config) {
          {
            auth: {
              'provider' => 'dummy'
            }
          }
        }
        let(:username_str) { 'admin' }
        let(:password_str) { 's3cr3t' }

        it 'returns a 401 if not authed' do
          get "#{prefix}/token"
          expect_json(ok = false, http = 401)
        end

        it 'returns a list of tokens if authed' do
          create_token "abc", "admin", current_time

          authorize 'admin', 's3cr3t'
          get "#{prefix}/token"
          expect_json(ok = true, http = 200)

          expect(JSON.parse(last_response.body)['abc']['created']).to eq(current_time.to_s)
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
        let(:config) {
          {
            auth: {
              'provider' => 'dummy'
            }
          }
        }

        it 'returns a 401 if not authed' do
          post "#{prefix}/token"
          expect_json(ok = false, http = 401)
        end

        it 'returns a newly created token if authed' do
          authorize 'admin', 's3cr3t'
          post "#{prefix}/token"
          expect_json(ok = true, http = 200)

          returned_token = JSON.parse(last_response.body)['token']
          expect(returned_token.length).to be(32)
          expect(get_token_data(returned_token)['user']).to eq("admin")
        end
      end
    end
  end

  describe '/token/:token' do
    let(:prefix) { '/api/v1' }
    let(:current_time) { Time.now }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute(['api'], config, redis, nil)
      app.settings.set :config, config
      app.settings.set :redis, redis
    end

    def create_vm_for_token(token, pool, vm)
      redis.sadd("vmpooler__running__#{pool}", vm)
      redis.hset("vmpooler__vm__#{vm}", "token:token", token)
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
          create_token "mytoken", "admin", current_time
          create_vm_for_token "mytoken", "pool1", "vmhostname"

          get "#{prefix}/token/mytoken"
          expect_json(ok = true, http = 200)

          expect(JSON.parse(last_response.body)['ok']).to eq(true)
          expect(JSON.parse(last_response.body)['mytoken']['user']).to eq('admin')
          expect(JSON.parse(last_response.body)['mytoken']['vms']['running']).to include('vmhostname')
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
        let(:config) {
          {
            auth: {
              'provider' => 'dummy'
            }
          }
        }

        it 'returns a 401 if not authed' do
          delete "#{prefix}/token/this"
          expect_json(ok = false, http = 401)
        end

        it 'deletes a token if authed' do
          create_token("mytoken", "admin", current_time)
          authorize 'admin', 's3cr3t'

          delete "#{prefix}/token/mytoken"
          expect_json(ok = true, http = 200)
        end

        it 'fails if token does not exist' do
          authorize 'admin', 's3cr3t'

          delete "#{prefix}/token/missingtoken"
          expect_json(ok = false, http = 401)  # TODO: should this be 404?
        end
      end
    end
  end
end
