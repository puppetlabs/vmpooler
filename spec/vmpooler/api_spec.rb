require 'spec_helper'
require 'rack/test'

describe Vmpooler::API do
  include Rack::Test::Methods

  def app()
    described_class
  end

  describe 'Dashboard' do

    context '/' do
      let(:config) { {
          config: {'site_name' => 'test pooler'}
      } }

      before do
        $config = config
        get '/'
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
      let(:redis) { double('redis') }

      before do
        $config = config
        app.settings.set :config, config
        app.settings.set :redis, redis
        app.settings.set :environment, :test
      end

      context 'without history param' do

        it 'returns basic JSON' do
          allow(redis).to receive(:scard)
          allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(3)
          allow(redis).to receive(:scard).with('vmpooler__ready__pool2').and_return(2)

          expect(redis).to receive(:scard).twice

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
        it 'returns JSON with null history when redis does not has values' do
          allow(redis).to receive(:scard)
          expect(redis).to receive(:scard).exactly(4).times

          get '/dashboard/stats/vmpooler/pool', :history => true

          json_hash = {
              pool1: {size: 5, ready: nil, history: [nil]},
              pool2: {size: 1, ready: nil, history: [nil]}
          }

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end

        it 'returns JSON with history when redis has values' do
          allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(3)
          allow(redis).to receive(:scard).with('vmpooler__ready__pool2').and_return(2)

          expect(redis).to receive(:scard).exactly(4).times

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
      let(:redis) { double('redis') }

      before do
        $config = config
        app.settings.set :config, config
        app.settings.set :redis, redis
        app.settings.set :environment, :test
      end

      context 'without history param' do

        it 'returns basic JSON' do
          allow(redis).to receive(:scard)

          expect(redis).to receive(:scard).exactly(3).times

          get '/dashboard/stats/vmpooler/running'

          json_hash = {pool: {running: 0}, diffpool: {running: 0}}

          expect(last_response).to be_ok
          expect(last_response.body).to eq(JSON.pretty_generate(json_hash))
          expect(last_response.header['Content-Type']).to eq('application/json')
        end

        it 'adds major correctly' do
          allow(redis).to receive(:scard).with('vmpooler__running__pool-1').and_return(3)
          allow(redis).to receive(:scard).with('vmpooler__running__pool-2').and_return(5)
          allow(redis).to receive(:scard).with('vmpooler__running__diffpool-1').and_return(2)

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