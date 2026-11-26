# frozen_string_literal: true

require 'spec_helper'

describe Vmpooler::Metrics::Promstats do
  let(:logger) { double('logger', log: nil) }
  let(:params) { { 'prefix' => 'test', 'prometheus_prefix' => 'mtest', 'prometheus_endpoint' => 'eptest' } }
  let(:prometheus) { described_class.new(logger, params) }

  describe 'a metric that cannot be recorded' do
    it 'logs a failed increment and carries on' do
      expect { prometheus.increment('bogus') }.not_to raise_error

      expect(logger).to have_received(:log).with('s', /prometheus error logging metric bogus increment : /)
    end

    it 'logs a failed gauge and carries on' do
      expect { prometheus.gauge('bogus', 3) }.not_to raise_error

      expect(logger).to have_received(:log).with('s', /prometheus error logging gauge bogus, value 3: /)
    end

    it 'logs a failed timing and carries on' do
      expect { prometheus.timing('bogus', 2.5) }.not_to raise_error

      expect(logger).to have_received(:log).with('s', /prometheus error logging timing event label bogus, duration 2.5: /)
    end
  end

  describe 'a missing value' do
    it 'does not set a gauge without a value, and logs nothing' do
      prometheus.gauge('bogus', nil)

      expect(logger).not_to have_received(:log)
    end

    it 'does not record a timing without a duration, and logs nothing' do
      prometheus.timing('bogus', nil)

      expect(logger).not_to have_received(:log)
    end
  end
end
