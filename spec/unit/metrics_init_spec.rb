# frozen_string_literal: true

require 'spec_helper'

describe Vmpooler::Metrics do
  let(:logger) { MockLogger.new }

  describe '.init' do
    it 'uses statsd when it is configured' do
      expect(Vmpooler::Metrics::Statsd).to receive(:new).with(logger, { 'server' => 'statsd.example' }).and_return(:statsd)

      expect(described_class.init(logger, statsd: { 'server' => 'statsd.example' })).to eq(:statsd)
    end

    it 'uses graphite when it is configured' do
      expect(Vmpooler::Metrics::Graphite).to receive(:new).with(logger, { 'server' => 'graphite.example' }).and_return(:graphite)

      expect(described_class.init(logger, graphite: { 'server' => 'graphite.example' })).to eq(:graphite)
    end

    it 'uses prometheus when it is configured' do
      expect(Vmpooler::Metrics::Promstats).to receive(:new).with(logger, { 'prefix' => 'vmpooler' }).and_return(:prometheus)

      expect(described_class.init(logger, prometheus: { 'prefix' => 'vmpooler' })).to eq(:prometheus)
    end

    it 'prefers statsd, then graphite, then prometheus' do
      allow(Vmpooler::Metrics::Statsd).to receive(:new).and_return(:statsd)
      allow(Vmpooler::Metrics::Graphite).to receive(:new).and_return(:graphite)

      expect(described_class.init(logger, graphite: {}, statsd: {})).to eq(:statsd)
      expect(described_class.init(logger, prometheus: {}, graphite: {})).to eq(:graphite)
    end

    it 'sends metrics nowhere when none is configured' do
      expect(described_class.init(logger, {})).to be_a(Vmpooler::Metrics::DummyStatsd)
    end
  end
end
