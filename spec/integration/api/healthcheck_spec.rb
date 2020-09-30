require 'spec_helper'
require 'rack/test'

describe Vmpooler::API::Healthcheck do
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

  let(:config) {
    {
        config: {
            'site_name' => 'test pooler',
            'vm_lifetime_auth' => 2,
        },
        pools: [
                    {'name' => 'pool1', 'size' => 5, 'alias' => ['poolone', 'poolun']},
                    {'name' => 'pool2', 'size' => 10},
                    {'name' => 'pool3', 'size' => 10, 'alias' => 'NotArray'}
                ]
    }
  }

  let(:current_time) { Time.now }

  let(:metrics) {
    double("metrics")
  }

  before(:each) do
    expect(app).to receive(:run!).once
    expect(metrics).to receive(:setup_prometheus_metrics)
    expect(metrics).to receive(:prometheus_prefix)
    expect(metrics).to receive(:prometheus_endpoint)
    app.execute([:api], config, redis, metrics, nil)
    app.settings.set :config, auth: false
  end

  describe '/healthcheck' do
    it 'returns OK' do
      get "/healthcheck"
      expect(last_response.header['Content-Type']).to eq('application/json')
      expect(last_response.status).to eq(200)
      result = JSON.parse(last_response.body)
      expect(result).to eq({'ok' => true})
    end
  end
end
