# frozen_string_literal: true

module Vmpooler
  class Metrics
    # static class instantiate appropriate metrics object.
    def self.init(params)
      if params[:statsd]
        metrics = Vmpooler::Statsd.new(params[:statsd])
      elsif params[:graphite]
        metrics = Vmpooler::Graphite.new(params[:graphite])
      elsif params[:prometheus]
        metrics = Vmpooler::Promstats.new(params[:prometheus])
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
