# frozen_string_literal: true

module Vmpooler
  class Metrics
    # static class instantiate appropriate metrics object.
    def self.init(logger, params)
      if params[:statsd]
        metrics = Vmpooler::Statsd.new(logger, params[:statsd])
      elsif params[:graphite]
        metrics = Vmpooler::Graphite.new(logger, params[:graphite])
      elsif params[:prometheus]
        metrics = Vmpooler::Promstats.new(logger, params[:prometheus])
      else
        metrics = Vmpooler::DummyStatsd.new
      end
      metrics
    end
  end
end

require 'vmpooler/metrics/statsd'
require 'vmpooler/metrics/dummy_statsd'
require 'vmpooler/metrics/graphite'
require 'vmpooler/metrics/promstats'
