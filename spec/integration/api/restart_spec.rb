require 'spec_helper'
require 'rack/test'




describe Vmpooler::API::Restart do
  include Rack::Test::Methods
  let(:backend) { MockRedis.new }
  
  def app()
    Vmpooler::API
  end

  # Added to ensure no leakage in rack state from previous tests.
  # Removes all routes, filters, middleware and extension hooks from the current class
  # https://rubydoc.info/gems/sinatra/Sinatra/Base#reset!-class_method 
  before(:each) do
    app.reset!
    allow_any_instance_of(Vmpooler::API::Restart).to receive(:exit_process)
  end



  describe '/restart' do  
    let(:current_time) { Time.now } 
    let(:config) { { 
      config: {}
    } }

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, nil, nil)
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end


      context 'when restart endpoint is called' do

        it 'returns a 401 if no token is provided' do
          get "/restart/"
            expect(ok = false)
            expect(last_response.status).to eq(401)
        end

        it 'vmpooler restarts and returns a 200 when a token is provided' do
          
          get "/restart/"

            expect(last_response.header['Content-Type']).to eq('application/json') 
            expect(last_response.status).to eq(200) 
            expect(last_response.body).to eq(JSON.pretty_generate({ 'ok' => true, 'message' => 'Restarting ...' })) 
        end
      end
  end  
end