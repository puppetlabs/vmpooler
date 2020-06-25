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

  # Added to ensure no leakage in rack state from previous tests.
  # Removes all routes, filters, middleware and extension hooks from the current class
  # https://rubydoc.info/gems/sinatra/Sinatra/Base#reset!-class_method 
  before(:each) do
    app.reset!
  end

  describe 'status and metrics endpoints' do
    let(:prefix) { '/api/v1' }

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

    before(:each) do
      expect(app).to receive(:run!).once
      app.execute([:api], config, redis, nil)
      app.settings.set :config, auth: false
      create_token('abcdefghijklmnopqrstuvwxyz012345', 'jdoe', current_time)
    end

    describe 'GET /status' do
      it 'returns the configured maximum size for each pool' do
        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"]["pool1"]["max"]).to be(5)
        expect(result["pools"]["pool2"]["max"]).to be(10)
      end

      it 'returns the number of ready vms for each pool' do
        3.times {|i| create_ready_vm("pool1", "vm-#{i}", redis) }
        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"]["pool1"]["ready"]).to be(3)
        expect(result["pools"]["pool2"]["ready"]).to be(0)
      end

      it 'returns the number of running vms for each pool' do
        3.times {|i| create_running_vm("pool1", "vm-#{i}", redis) }
        4.times {|i| create_running_vm("pool2", "vm-#{i}", redis) }

        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"]["pool1"]["running"]).to be(3)
        expect(result["pools"]["pool2"]["running"]).to be(4)
      end

      it 'returns the number of pending vms for each pool' do
        3.times {|i| create_pending_vm("pool1", "vm-#{i}", redis) }
        4.times {|i| create_pending_vm("pool2", "vm-#{i}", redis) }

        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"]["pool1"]["pending"]).to be(3)
        expect(result["pools"]["pool2"]["pending"]).to be(4)
      end

      it 'returns aliases if configured in the pool' do
        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"]["pool1"]["alias"]).to eq(['poolone', 'poolun'])
        expect(result["pools"]["pool2"]["alias"]).to be(nil)
        expect(result["pools"]["pool3"]["alias"]).to eq('NotArray')
      end

      it '(for v1 backwards compatibility) lists any empty pools in the status section' do
        get "#{prefix}/status/"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["status"]["empty"].sort).to eq(["pool1", "pool2", "pool3"])
      end
    end
    describe 'GET /status with view query parameter' do
      it 'returns capacity when specified' do
        get "#{prefix}/status?view=capacity"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to_not be(nil)
        expect(result["queue"]).to be(nil)
        expect(result["clone"]).to be(nil)
        expect(result["boot"]).to be(nil)
        expect(result["pools"]).to be(nil)
        expect(result["status"]).to_not be(nil)
      end
      it 'returns pools and queue when specified' do
        get "#{prefix}/status?view=pools,queue"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to be(nil)
        expect(result["queue"]).to_not be(nil)
        expect(result["clone"]).to be(nil)
        expect(result["boot"]).to be(nil)
        expect(result["pools"]).to_not be(nil)
        expect(result["status"]).to_not be(nil)
      end
      it 'does nothing with invalid view names' do
        get "#{prefix}/status?view=clone,boot,invalidThingToView"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to be(nil)
        expect(result["queue"]).to be(nil)
        expect(result["clone"]).to_not be(nil)
        expect(result["boot"]).to_not be(nil)
        expect(result["pools"]).to be(nil)
        expect(result["status"]).to_not be(nil)
      end
      it 'returns everything when view is not specified' do
        get "#{prefix}/status"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to_not be(nil)
        expect(result["queue"]).to_not be(nil)
        expect(result["clone"]).to_not be(nil)
        expect(result["boot"]).to_not be(nil)
        expect(result["pools"]).to_not be(nil)
        expect(result["status"]).to_not be(nil)
      end
      it 'returns everything when view is alone' do
        get "#{prefix}/status?view"

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to_not be(nil)
        expect(result["queue"]).to_not be(nil)
        expect(result["clone"]).to_not be(nil)
        expect(result["boot"]).to_not be(nil)
        expect(result["pools"]).to_not be(nil)
        expect(result["status"]).to_not be(nil)
      end
      it 'returns status only when view is empty' do
        get "#{prefix}/status?view="

        # of course /status doesn't conform to the weird standard everything else uses...
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["capacity"]).to be(nil)
        expect(result["queue"]).to be(nil)
        expect(result["clone"]).to be(nil)
        expect(result["boot"]).to be(nil)
        expect(result["pools"]).to be(nil)
        expect(result["status"]).to_not be(nil)
      end
    end

    describe 'GET /poolstat' do
      it 'returns empty list when pool is not set' do
        get "#{prefix}/poolstat"
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result  == {})
      end
      it 'returns empty list when pool is not found' do
        get "#{prefix}/poolstat?pool=unknownpool"
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result  == {})
      end
      it 'returns one pool when requesting one with alias' do
        get "#{prefix}/poolstat?pool=pool1"
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"].size == 1)
        expect(result["pools"]["pool1"]["ready"]).to eq(0)
        expect(result["pools"]["pool1"]["max"]).to eq(5)
        expect(result["pools"]["pool1"]["alias"]).to eq(['poolone', 'poolun'])
      end
      it 'returns one pool when requesting one without alias' do
        get "#{prefix}/poolstat?pool=pool2"
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"].size == 1)
        expect(result["pools"]["pool2"]["ready"]).to eq(0)
        expect(result["pools"]["pool2"]["max"]).to eq(10)
        expect(result["pools"]["pool2"]["alias"]).to be(nil)
      end
      it 'returns multiple pools when requesting csv' do
        get "#{prefix}/poolstat?pool=pool1,pool2"
        expect(last_response.header['Content-Type']).to eq('application/json')
        result = JSON.parse(last_response.body)
        expect(result["pools"].size == 2)
      end
    end

    describe 'GET /totalrunning' do
      it 'returns the number of running VMs' do
        get "#{prefix}/totalrunning"
        expect(last_response.header['Content-Type']).to eq('application/json')
        5.times {|i| create_running_vm("pool1", "vm-#{i}", redis, redis) }
        5.times {|i| create_running_vm("pool3", "vm-#{i}", redis, redis) }
        result = JSON.parse(last_response.body)
        expect(result["running"] == 10)
      end
    end
  end
end
