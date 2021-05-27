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

    it 'returns OK' do
      get "/restart"
      
      expect(last_response.status).to eq(200)
      result = JSON.parse(last_response.body)
      expect(result).to eq({'ok' => true})
    end 
  end  
end