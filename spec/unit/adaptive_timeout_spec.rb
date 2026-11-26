# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/adaptive_timeout'

describe Vmpooler::AdaptiveTimeout do
  let(:logger) { double('logger', log: nil) }
  let(:metrics) { double('metrics', gauge: nil) }
  let(:max) { 60 }
  let(:tracker) do
    described_class.new(name: 'vsphere', logger: logger, metrics: metrics,
                        min: 5, max: max, initial: 30, max_samples: 20)
  end

  def record(duration, times = 1)
    times.times { tracker.record_success(duration) }
  end

  describe 'a new tracker' do
    it 'starts at the initial timeout' do
      expect(tracker.timeout).to eq(30)
      expect(tracker.current_timeout).to eq(30)
    end

    it 'has defaults of 30 seconds between 5 and 60' do
      defaults = described_class.new(name: 'x', logger: logger, metrics: metrics)

      expect(defaults.timeout).to eq(30)
      defaults.record_failure
      expect(defaults.timeout).to eq(24)
    end
  end

  describe '#record_success' do
    it 'does not change the timeout before there are 10 samples' do
      record(2.0, 9)

      expect(tracker.timeout).to eq(30)
    end

    it 'sets the timeout to the p95 duration plus 50% once there are 10 samples' do
      record(10.0, 10)

      expect(tracker.timeout).to eq(15)
      expect(metrics).to have_received(:gauge).with('adaptive_timeout.current.vsphere', 15)
      expect(metrics).to have_received(:gauge).with('adaptive_timeout.p95.vsphere', 10.0)
      expect(logger).to have_received(:log).with('d', /adjusted timeout 30s → 15s \(p95: 10\.0s\)/)
    end

    it 'leaves the timeout alone when the change is 5 seconds or less' do
      record(18.0, 10) # 18 * 1.5 = 27, only 3 below 30

      expect(tracker.timeout).to eq(30)
      expect(metrics).not_to have_received(:gauge)
    end

    it 'never goes above the maximum' do
      record(100.0, 10)

      expect(tracker.timeout).to eq(60)
    end

    it 'never goes below the minimum' do
      record(0.5, 10)

      expect(tracker.timeout).to eq(5)
    end

    it 'follows a slowdown as slow samples push out the fast ones' do
      record(4.0, 20)
      expect(tracker.timeout).to eq(6) # 4 * 1.5

      record(40.0, 20)
      expect(tracker.timeout).to eq(60)
    end

    it 'keeps only the most recent samples' do
      (1..25).each { |n| tracker.record_success(n.to_f) }

      stats = tracker.stats
      expect(stats[:samples]).to eq(20)
      expect(stats[:min]).to eq(6.0)
      expect(stats[:max]).to eq(25.0)
    end
  end

  describe '#record_failure' do
    it 'cuts the timeout by 20%' do
      tracker.record_failure

      expect(tracker.timeout).to eq(24)
      expect(logger).to have_received(:log).with('d', /reduced timeout 30s → 24s after failure/)
      expect(metrics).to have_received(:gauge).with('adaptive_timeout.current.vsphere', 24)
    end

    it 'keeps cutting, down to the minimum' do
      10.times { tracker.record_failure }

      expect(tracker.timeout).to eq(5)
    end

    it 'says nothing when it is already at the minimum' do
      at_minimum = described_class.new(name: 'vsphere', logger: logger, metrics: metrics,
                                       min: 5, max: 60, initial: 5)

      at_minimum.record_failure

      expect(at_minimum.timeout).to eq(5)
      expect(logger).not_to have_received(:log)
      expect(metrics).not_to have_received(:gauge)
    end
  end

  describe '#reset' do
    it 'goes back to 30 seconds and forgets the samples' do
      record(10.0, 10)
      expect(tracker.timeout).to eq(15)

      tracker.reset

      expect(tracker.timeout).to eq(30)
      expect(tracker.stats).to eq(samples: 0)
      expect(logger).to have_received(:log).with('d', /reset timeout 15s → 30s/)
      expect(metrics).to have_received(:gauge).with('adaptive_timeout.current.vsphere', 30)
    end

    context 'with a maximum below 30 seconds' do
      let(:max) { 20 }

      it 'goes back to the maximum' do
        tracker.reset

        expect(tracker.timeout).to eq(20)
      end
    end
  end

  describe '#stats' do
    it 'reports no samples when there are none' do
      expect(tracker.stats).to eq(samples: 0)
    end

    it 'summarises the recent durations' do
      [1.0, 2.0, 3.0, 4.0, 5.0].each { |d| tracker.record_success(d) }

      expect(tracker.stats).to eq(samples: 5, min: 1.0, max: 5.0, avg: 3.0, p50: 3.0, p95: 5.0, p99: 5.0,
                                  current_timeout: 30)
    end

    it 'rounds to two decimals' do
      [1.234, 2.345].each { |d| tracker.record_success(d) }

      expect(tracker.stats).to include(min: 1.23, max: 2.35, avg: 1.79)
    end

    it 'reports the current timeout' do
      tracker.record_failure
      tracker.record_success(1.0)

      expect(tracker.stats[:current_timeout]).to eq(24)
    end
  end

  describe 'used from several threads' do
    it 'does not lose samples or raise' do
      threads = Array.new(8) { Thread.new { 10.times { tracker.record_success(1.0) } } }
      expect { threads.each(&:join) }.not_to raise_error

      expect(tracker.stats[:samples]).to eq(20)
    end
  end
end
