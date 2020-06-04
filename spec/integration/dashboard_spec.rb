require 'spec_helper'
require 'rack/test'

describe Vmpooler::API do
  include Rack::Test::Methods

  def app()
    described_class
  end

  describe 'Dashboard' do

    context '/' do
      before { get '/' }

      it { expect(last_response.status).to eq(302) }
      it { expect(last_response.location).to eq('http://example.org/dashboard/') }
    end

    context '/dashboard/' do
      ENV['SITE_NAME'] = 'test pooler'
      ENV['VMPOOLER_CONFIG'] = 'thing'

      before do
        get '/dashboard/'
      end

      it { expect(last_response).to be_ok }
      it { expect(last_response.body).to match(/test pooler/) }
      it { expect(last_response.body).not_to match(/<b>vmpooler<\/b>/) }
    end

    context 'unknown route' do
      before { get '/doesnotexist' }

      it { expect(last_response.status).to eq(404) }
      it { expect(last_response.header['Content-Type']).to eq('application/json') }
      it { expect(last_response.body).to eq(JSON.pretty_generate({ok: false})) }
    end

    describe '/dashboard/stats/vmpooler/pool' do
      let(:config) { {
          pools: [
              {'name' => 'pool1', 'size' => 5},
              {'name' => 'pool2', 'size' => 1}
          ],
          graphite: {}
      } }

      before do
        $config = config
        app.settings.set :config, config
        app.settings.set :redis, redis
        app.settings.set :environment, :test
      end

      context 'without history param' do
        it 'returns basic JSON' do
          create_ready_vm('pool1', 'vm1', redis)
          create_ready_vm('pool1', 'vm2', redis)
          create_ready_vm('pool1', 'vm3', redis)
          create_ready_vm('pool2', 'vm4', redis)
          create_ready_vm('pool2', 'vm5', redis)

          get '/dashboard/stats/vmpooler/pool'

          json_hash = {
              pool1: {size: 5, ready: 3},
              pool2: {size: 1, ready: 2}
          }

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end
      end

      context 'with history param' do
        it 'returns JSON with zeroed history when redis does not have values' do
          get '/dashboard/stats/vmpooler/pool', :history => true

          json_hash = {
              pool1: {size: 5, ready: 0, history: [0]},
              pool2: {size: 1, ready: 0, history: [0]}
          }

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end

        it 'returns JSON with history when redis has values' do
          create_ready_vm('pool1', 'vm1', redis)
          create_ready_vm('pool1', 'vm2', redis)
          create_ready_vm('pool1', 'vm3', redis)
          create_ready_vm('pool2', 'vm4', redis)
          create_ready_vm('pool2', 'vm5', redis)

          get '/dashboard/stats/vmpooler/pool', :history => true

          json_hash = {
              pool1: {size: 5, ready: 3, history: [3]},
              pool2: {size: 1, ready: 2, history: [2]}
          }

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end
      end
    end

    describe '/dashboard/stats/vmpooler/running' do
      let(:config) { {
          pools: [
              {'name' => 'pool-1', 'size' => 5},
              {'name' => 'pool-2', 'size' => 1},
              {'name' => 'diffpool-1', 'size' => 3}
          ],
          graphite: {}
      } }

      before do
        $config = config
        app.settings.set :config, config
        app.settings.set :redis, redis
        app.settings.set :environment, :test
      end

      context 'without history param' do

        it 'returns basic JSON' do
          get '/dashboard/stats/vmpooler/running'

          json_hash = {pool: {running: 0}, diffpool: {running: 0}}

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end

        it 'adds major correctly' do
          create_running_vm('pool-1', 'vm1', redis)
          create_running_vm('pool-1', 'vm2', redis)
          create_running_vm('pool-1', 'vm3', redis)

          create_running_vm('pool-2', 'vm4', redis)
          create_running_vm('pool-2', 'vm5', redis)
          create_running_vm('pool-2', 'vm6', redis)
          create_running_vm('pool-2', 'vm7', redis)
          create_running_vm('pool-2', 'vm8', redis)

          create_running_vm('diffpool-1', 'vm9', redis)
          create_running_vm('diffpool-1', 'vm10', redis)

          get '/dashboard/stats/vmpooler/running'

          json_hash = {pool: {running: 8}, diffpool: {running: 2}}

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end
      end
    end
  end
end
