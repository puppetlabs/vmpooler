# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/metrics/graphite'

describe Vmpooler::Metrics::Graphite do
  let(:logger) { double('logger', log: nil) }
  let(:params) { { 'server' => 'graphite.example' } }
  let(:graphite) { described_class.new(logger, params) }
  let(:socket) { double('socket', puts: nil, close: nil) }
  let(:now) { Time.at(1_700_000_000) }

  describe '#initialize' do
    it 'needs a server' do
      expect { described_class.new(logger, {}) }.to raise_error(ArgumentError, /Graphite server is required/)
      expect { described_class.new(logger, 'server' => '') }.to raise_error(ArgumentError, /Graphite server is required/)
    end

    it 'defaults to port 2003 and the prefix "vmpooler"' do
      expect(graphite.server).to eq('graphite.example')
      expect(graphite.port).to eq(2003)
      expect(graphite.prefix).to eq('vmpooler')
    end

    it 'takes a port and a prefix' do
      custom = described_class.new(logger, params.merge('port' => 2004, 'prefix' => 'mypool'))

      expect(custom.port).to eq(2004)
      expect(custom.prefix).to eq('mypool')
    end
  end

  describe 'sending a metric' do
    before do
      allow(Time).to receive(:now).and_return(now)
      allow(TCPSocket).to receive(:new).with('graphite.example', 2003).and_return(socket)
    end

    {
      increment: ['clone', 1],
      gauge: ['ready.pool1', 5],
      timing: ['clone.duration', 12.5]
    }.each do |method, (label, value)|
      it "sends #{method} as a plaintext line with the prefix and the time" do
        args = method == :increment ? [label] : [label, value]

        graphite.public_send(method, *args).join

        expect(socket).to have_received(:puts).with("vmpooler.#{label} #{value} 1700000000")
        expect(socket).to have_received(:close)
      end
    end

    it 'closes the socket when sending fails' do
      allow(socket).to receive(:puts).and_raise(IOError, 'broken pipe')
      old = Thread.report_on_exception
      Thread.report_on_exception = false

      thread = graphite.gauge('x', 1)
      expect { thread.join }.to raise_error(IOError)
      expect(socket).to have_received(:close)
    ensure
      Thread.report_on_exception = old
    end
  end

  describe 'when the metric thread cannot be started' do
    it 'warns about an address it cannot use' do
      allow(Thread).to receive(:new).and_raise(Errno::EADDRNOTAVAIL)

      expect { graphite.gauge('x', 1) }.to output(/Could not assign address to graphite server graphite.example/).to_stderr
    end

    it 'logs any other failure' do
      allow(Thread).to receive(:new).and_raise(StandardError, 'no threads left')

      graphite.gauge('x', 1)

      expect(logger).to have_received(:log).with('s', /Failure logging x to graphite server \[graphite.example:2003\]: no threads left/)
    end
  end
end
