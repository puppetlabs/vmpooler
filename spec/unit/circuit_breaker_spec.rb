# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/circuit_breaker'

describe Vmpooler::CircuitBreaker do
  let(:logger) { double('logger', log: nil) }
  let(:metrics) { double('metrics', increment: nil, gauge: nil) }
  let(:breaker) do
    described_class.new(name: 'vsphere', logger: logger, metrics: metrics,
                        failure_threshold: 3, timeout: 30, half_open_attempts: 2)
  end

  before do
    @clock = Time.at(1_700_000_000)
    allow(Time).to receive(:now) { @clock }
  end

  def advance(seconds)
    @clock += seconds
  end

  def fail_once
    expect { breaker.call { raise 'boom' } }.to raise_error('boom')
  end

  def open_the_circuit
    3.times { fail_once }
  end

  describe 'a new breaker' do
    it 'starts closed with nothing counted' do
      expect(breaker.state).to eq(:closed)
      expect(breaker.failure_count).to eq(0)
      expect(breaker.success_count).to eq(0)
    end

    it 'has defaults of 5 failures, 30 seconds and 3 test requests' do
      defaults = described_class.new(name: 'x', logger: logger, metrics: metrics)

      5.times { expect { defaults.call { raise 'boom' } }.to raise_error('boom') }
      expect(defaults.state).to eq(:open)
      advance(30)
      3.times { defaults.call { :ok } }
      expect(defaults.state).to eq(:closed)
    end
  end

  describe 'when closed' do
    it 'returns what the block returns' do
      expect(breaker.call { :result }).to eq(:result)
    end

    it 'lets the original error through and counts it' do
      fail_once

      expect(breaker.failure_count).to eq(1)
      expect(breaker.state).to eq(:closed)
    end

    it 'stays closed below the failure threshold' do
      2.times { fail_once }

      expect(breaker.state).to eq(:closed)
    end

    it 'forgets earlier failures after a success' do
      2.times { fail_once }
      breaker.call { :ok }
      2.times { fail_once }

      expect(breaker.state).to eq(:closed)
      expect(breaker.failure_count).to eq(2)
    end

    it 'opens when the failure threshold is reached' do
      open_the_circuit

      expect(breaker.state).to eq(:open)
      expect(breaker.failure_count).to eq(3)
    end
  end

  describe 'when open' do
    before { open_the_circuit }

    it 'refuses calls without running the block' do
      ran = false

      expect { breaker.call { ran = true } }.to raise_error(described_class::CircuitOpenError)
      expect(ran).to be false
    end

    it 'says how long until it will try again' do
      advance(10)

      expect { breaker.call { :ok } }.to raise_error(described_class::CircuitOpenError,
                                                     /'vsphere' is open \(3 failures, retry in 20\.0s\)/)
    end

    it 'does not allow requests before the timeout' do
      advance(29)

      expect(breaker.allow_request?).to be false
    end

    it 'allows a request once the timeout has passed, without changing state' do
      advance(30)

      expect(breaker.allow_request?).to be true
      expect(breaker.state).to eq(:open)
    end

    it 'counts another failure while open without changing state' do
      breaker.send(:on_failure, StandardError.new('late'))

      expect(breaker.failure_count).to eq(4)
      expect(breaker.state).to eq(:open)
      expect(logger).to have_received(:log).with('d', /additional failure while open/)
    end

    it 'closes if a success is somehow recorded' do
      breaker.send(:on_success)

      expect(breaker.state).to eq(:closed)
    end
  end

  describe 'after the timeout' do
    before do
      open_the_circuit
      advance(31)
    end

    it 'goes half open and runs the next call' do
      expect(breaker.call { :probe }).to eq(:probe)

      expect(breaker.state).to eq(:half_open)
      expect(breaker.success_count).to eq(1)
    end

    it 'closes after the required number of successful test calls' do
      2.times { breaker.call { :ok } }

      expect(breaker.state).to eq(:closed)
      expect(breaker.failure_count).to eq(0)
      expect(breaker.success_count).to eq(0)
    end

    it 'opens again at once if a test call fails' do
      breaker.call { :ok }

      fail_once

      expect(breaker.state).to eq(:open)
      expect(breaker.success_count).to eq(0)
    end

    it 'allows requests while half open' do
      breaker.call { :ok }

      expect(breaker.allow_request?).to be true
    end

    it 'waits a full timeout again after a failed test call' do
      fail_once
      advance(10)

      expect { breaker.call { :ok } }.to raise_error(described_class::CircuitOpenError, /retry in 20\.0s/)
    end
  end

  describe '#allow_request?' do
    it 'is true when closed' do
      expect(breaker.allow_request?).to be true
    end
  end

  describe '#status' do
    it 'describes a closed breaker' do
      expect(breaker.status).to eq(name: 'vsphere', state: :closed, failure_count: 0, success_count: 0,
                                   last_failure_time: nil, next_retry_time: nil)
    end

    it 'gives the next retry time when open' do
      open_the_circuit

      status = breaker.status
      expect(status[:state]).to eq(:open)
      expect(status[:last_failure_time]).to eq(@clock)
      expect(status[:next_retry_time]).to eq(@clock + 30)
    end

    it 'has no retry time when half open' do
      open_the_circuit
      advance(31)
      breaker.call { :ok }

      expect(breaker.status[:next_retry_time]).to be_nil
    end
  end

  describe 'logging and metrics' do
    it 'reports each transition' do
      open_the_circuit
      advance(31)
      2.times { breaker.call { :ok } }

      expect(metrics).to have_received(:increment).with('circuit_breaker.opened.vsphere')
      expect(metrics).to have_received(:increment).with('circuit_breaker.half_open.vsphere')
      expect(metrics).to have_received(:increment).with('circuit_breaker.closed.vsphere')
      expect(metrics).to have_received(:gauge).with('circuit_breaker.state.vsphere', 1)
      expect(metrics).to have_received(:gauge).with('circuit_breaker.state.vsphere', 0.5)
      expect(metrics).to have_received(:gauge).with('circuit_breaker.state.vsphere', 0)
      expect(logger).to have_received(:log).with('s', /OPENED after 3 failures \(will retry in 30s\)/)
      expect(logger).to have_received(:log).with('s', /HALF-OPEN/)
      expect(logger).to have_received(:log).with('s', /CLOSED, provider recovered/)
    end

    it 'logs each failure while closed and each good test call while half open' do
      fail_once
      expect(logger).to have_received(:log).with('d', /failure 1\/3: RuntimeError/)

      2.times { fail_once }
      advance(31)
      breaker.call { :ok }
      expect(logger).to have_received(:log).with('d', /successful test request \(1\/2\)/)
    end

    it 'logs a failure during the half-open test' do
      open_the_circuit
      advance(31)
      fail_once

      expect(logger).to have_received(:log).with('d', /failed during half-open test/)
    end

    it 'sends nothing to metrics when nothing changes state' do
      breaker.call { :ok }

      expect(metrics).not_to have_received(:increment)
      expect(metrics).not_to have_received(:gauge)
    end
  end
end
