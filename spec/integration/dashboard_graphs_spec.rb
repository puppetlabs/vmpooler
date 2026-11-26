# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'json'

# Which graph server the dashboard asks, worked out from the config.
describe Vmpooler::API::Dashboard do
  let(:dashboard) { described_class.new! }

  before { allow(dashboard).to receive(:config).and_return(config) }

  context 'with a graphs setting' do
    let(:config) { { graphs: { 'server' => 'graph.example', 'prefix' => 'mypool' } } }

    it 'uses its server and prefix' do
      expect(dashboard.graph_server).to eq('graph.example')
      expect(dashboard.graph_prefix).to eq('mypool')
      expect(dashboard.graph_url).to eq('http://graph.example/render?target=mypool')
    end

    it 'adds a target to the URL for a link' do
      expect(dashboard.graph_link('.ready.*')).to eq('http://graph.example/render?target=mypool.ready.*')
    end
  end

  context 'with a graphs setting that has no prefix' do
    let(:config) { { graphs: { 'server' => 'graph.example' } } }

    it 'uses "vmpooler" as the prefix' do
      expect(dashboard.graph_prefix).to eq('vmpooler')
    end
  end

  context 'with a graphs setting that has no server' do
    let(:config) { { graphs: { 'prefix' => 'mypool' } } }

    it 'has no graph server, so no URL and an empty link' do
      expect(dashboard.graph_server).to be false
      expect(dashboard.graph_url).to be false
      expect(dashboard.graph_link('.ready.*')).to eq('')
    end
  end

  context 'with the older graphite setting' do
    let(:config) { { graphite: { 'server' => 'graphite.example', 'prefix' => 'old' } } }

    it 'uses its server and prefix' do
      expect(dashboard.graph_server).to eq('graphite.example')
      expect(dashboard.graph_prefix).to eq('old')
      expect(dashboard.graph_url).to eq('http://graphite.example/render?target=old')
    end
  end

  context 'with a graphite setting that has a server but no prefix' do
    let(:config) { { graphite: { 'server' => 'graphite.example' } } }

    it 'has no prefix, so no URL' do
      expect(dashboard.graph_prefix).to be false
      expect(dashboard.graph_url).to be false
    end
  end

  context 'with a graphite setting that has a prefix but no server' do
    let(:config) { { graphite: { 'prefix' => 'old' } } }

    it 'has no server, so no URL' do
      expect(dashboard.graph_server).to be false
      expect(dashboard.graph_url).to be false
    end
  end

  context 'with no graph setting at all' do
    let(:config) { {} }

    it 'has nothing to ask' do
      expect(dashboard.graph_server).to be false
      expect(dashboard.graph_prefix).to be false
      expect(dashboard.graph_url).to be false
    end
  end
end

# The history the dashboard builds from a graph server.
describe Vmpooler::API do
  include Rack::Test::Methods

  def app
    Vmpooler::API
  end

  before(:each) do
    app.reset!
  end

  describe 'Dashboard history from graphs' do
    let(:pools) do
      [
        { 'name' => 'pool-1', 'size' => 5 },
        { 'name' => 'pool-2', 'size' => 1 }
      ]
    end
    let(:config) { { config: {}, pools: pools, graphite: {} } }
    let(:graph_url) { 'http://graph.example/render?target=mypool' }
    let(:graph_json) { '[]' }
    let(:reader) { double('graph response', read: graph_json) }
    let(:requested) { [] }

    before(:each) do
      expect(app).to receive(:run!)
      app.execute([:api], config, redis, nil, nil)
      app.settings.set :config, config
      app.settings.set :environment, :test

      # Decide the graph server here, whatever the config says, and answer its requests.
      allow_any_instance_of(Vmpooler::API::Dashboard).to receive(:graph_url).and_return(graph_url)
      calls = requested
      allow(URI).to receive(:parse).and_call_original
      allow(URI).to receive(:parse).with(%r{/render\?target=}) do |url|
        calls << url
        reader
      end
    end

    describe '/dashboard/stats/vmpooler/pool' do
      let(:graph_json) do
        JSON.generate([
                        { 'target' => 'mypool.ready.pool-1', 'datapoints' => [[3, 1], [nil, 2]] },
                        { 'target' => 'mypool.ready.unknown-pool', 'datapoints' => [[9, 1]] }
                      ])
      end

      it 'asks the ready graphs for the last hour' do
        get '/dashboard/stats/vmpooler/pool', history: true

        expect(requested).to eq(['http://graph.example/render?target=mypool.ready.*&from=-1hour&format=json'])
      end

      it 'builds each pool history from the graph, filling gaps with the last value' do
        get '/dashboard/stats/vmpooler/pool', history: true

        history = JSON.parse(last_response.body)['pool-1']['history']
        expect(history).to eq([3] * 16) # 8 points per datapoint, the gap repeats the last value
      end

      it 'ignores a graph for a pool that is not configured' do
        get '/dashboard/stats/vmpooler/pool', history: true

        expect(JSON.parse(last_response.body)).not_to have_key('unknown-pool')
      end

      it 'leaves a pool the graph does not mention without history' do
        get '/dashboard/stats/vmpooler/pool', history: true

        expect(JSON.parse(last_response.body)['pool-2']).not_to have_key('history')
      end

      it 'does not ask the graph server unless history is wanted' do
        get '/dashboard/stats/vmpooler/pool'

        expect(requested).to be_empty
      end

      it 'carries on without history when the graph server cannot be read' do
        allow(URI).to receive(:parse).with(%r{/render\?target=}).and_raise(StandardError, 'no route to host')

        get '/dashboard/stats/vmpooler/pool', history: true

        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)['pool-1']).to eq('size' => 5, 'ready' => 0)
      end

      it 'carries on without history when the graph server sends something that is not JSON' do
        allow(reader).to receive(:read).and_return('<html>oops</html>')

        get '/dashboard/stats/vmpooler/pool', history: true

        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)['pool-1']).to eq('size' => 5, 'ready' => 0)
      end
    end

    describe '/dashboard/stats/vmpooler/running' do
      let(:graph_json) do
        JSON.generate([
                        { 'target' => 'mypool.running.pool-1', 'datapoints' => [[2, 1], [4, 2]] },
                        { 'target' => 'mypool.running.pool-2', 'datapoints' => [[1, 1]] }
                      ])
      end

      it 'asks the running graphs for the last hour' do
        get '/dashboard/stats/vmpooler/running', history: true

        expect(requested).to eq(['http://graph.example/render?target=mypool.running.*&from=-1hour&format=json'])
      end

      it 'adds the pools of a major name together, repeating the last value past the end' do
        get '/dashboard/stats/vmpooler/running', history: true

        expect(JSON.parse(last_response.body)['pool']['history']).to eq([3, 5, 4])
      end

      it 'does not ask the graph server unless history is wanted' do
        get '/dashboard/stats/vmpooler/running'

        expect(requested).to be_empty
        expect(JSON.parse(last_response.body)['pool']).not_to have_key('history')
      end

      it 'carries on without history when the graph server cannot be read' do
        allow(URI).to receive(:parse).with(%r{/render\?target=}).and_raise(StandardError, 'no route to host')

        get '/dashboard/stats/vmpooler/running', history: true

        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)['pool']).to eq('running' => 0)
      end
    end
  end
end
