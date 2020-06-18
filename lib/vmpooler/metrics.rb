# frozen_string_literal: true

require 'vmpooler/metrics/statsd'
require 'vmpooler/metrics/graphite'
require 'vmpooler/metrics/promstats'
require 'vmpooler/metrics/dummy_statsd'

module Vmpooler
  class Metrics
    # static class instantiate appropriate metrics object.
    def self.init(logger, params)
      if params[:statsd]
        metrics = Vmpooler::Metrics::Statsd.new(logger, params[:statsd])
      elsif params[:graphite]
        metrics = Vmpooler::Metrics::Graphite.new(logger, params[:graphite])
      elsif params[:prometheus]
        metrics = Vmpooler::Metrics::Promstats.new(logger, params[:prometheus])
      else
        metrics = Vmpooler::Metrics::DummyStatsd.new
      end
      metrics
    end
  end
end
