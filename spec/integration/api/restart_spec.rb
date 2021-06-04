require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::Restart do
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



  describe '/restart' do  
    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, nil, nil)
    end

    
    describe 'GET /restart' do
      context '(auth not configured)' do
        let(:config) { { 
          config: {},
          auth: false 
          } }
    
        it 'returns a 404' do
          get "/restart"
            expect_json(ok = false, http = 404)
        end
      end


      context '(auth configured)' do
        let(:config) {
          {
            config: {},
            auth: {
              'provider' => 'dummy'
            }
          }
        }
        let(:username_str) { 'admin' }
        let(:password_str) { 's3cr3t' }
    
        it 'returns a 401 if no token is provided' do
          get "/restart"
            expect_json(ok = false, http = 401)
        end

        it 'restarts if token is provided' do
    
          authorize 'admin', 's3cr3t'
          get "/restart"
            expect_json(ok = true, http = 200)
    
            expect(JSON.parse(last_response.body).to eq JSON.parse(JSON.dump({ 'ok' => true, 'message' => 'Restarting ...' })))
          
        end
      end
    
    end

  end  
end