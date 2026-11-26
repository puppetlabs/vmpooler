# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/metrics/statsd'

describe Vmpooler::Metrics::Statsd do
  let(:logger) { double('logger', log: nil) }
  let(:params) { { 'server' => 'statsd.example' } }
  let(:client) { double('statsd client', increment: nil, gauge: nil, timing: nil) }
  let(:statsd) { described_class.new(logger, params) }

  before { allow(::Statsd).to receive(:new).and_return(client) }

  describe '#initialize' do
    it 'needs a server' do
      expect { described_class.new(logger, {}) }.to raise_error(ArgumentError, /Statsd server is required/)
      expect { described_class.new(logger, 'server' => '') }.to raise_error(ArgumentError, /Statsd server is required/)
    end

    it 'connects to the server on port 8125 by default, with the prefix "vmpooler"' do
      statsd

      expect(::Statsd).to have_received(:new).with('statsd.example', 8125)
      expect(statsd.port).to eq(8125)
      expect(statsd.prefix).to eq('vmpooler')
    end

    it 'takes a port and a prefix' do
      custom = described_class.new(logger, params.merge('port' => 9125, 'prefix' => 'mypool'))

      expect(::Statsd).to have_received(:new).with('statsd.example', 9125)
      expect(custom.prefix).to eq('mypool')
    end
  end

  describe 'sending metrics' do
    it 'increments a prefixed counter' do
      statsd.increment('clone')

      expect(client).to have_received(:increment).with('vmpooler.clone')
    end

    it 'sets a prefixed gauge' do
      statsd.gauge('ready.pool1', 5)

      expect(client).to have_received(:gauge).with('vmpooler.ready.pool1', 5)
    end

    it 'records a prefixed timing' do
      statsd.timing('clone.duration', 12.5)

      expect(client).to have_received(:timing).with('vmpooler.clone.duration', 12.5)
    end
  end

  describe 'when the server cannot be reached' do
    before do
      allow(client).to receive(:increment).and_raise(StandardError, 'refused')
      allow(client).to receive(:gauge).and_raise(StandardError, 'refused')
      allow(client).to receive(:timing).and_raise(StandardError, 'refused')
    end

    it 'logs the failed increment and carries on' do
      expect { statsd.increment('clone') }.not_to raise_error
      expect(logger).to have_received(:log).with('s', /Failure incrementing vmpooler.clone on statsd server .*: refused/)
    end

    it 'logs the failed gauge and carries on' do
      expect { statsd.gauge('ready', 1) }.not_to raise_error
      expect(logger).to have_received(:log).with('s', /Failure updating gauge vmpooler.ready on statsd server .*: refused/)
    end

    it 'logs the failed timing and carries on' do
      expect { statsd.timing('clone', 1) }.not_to raise_error
      expect(logger).to have_received(:log).with('s', /Failure updating timing vmpooler.clone on statsd server .*: refused/)
    end
  end
end
