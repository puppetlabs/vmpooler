require 'rubygems' unless defined?(Gem)

module Vmpooler
  class Statsd
    attr_reader :server, :port, :prefix

    def initialize(params = {})
      if params[:server].nil? || params[:server].empty?
        raise ArgumentError, "Statsd server is required. Config: #{params.inspect}"
      end

      host    = params[:server]
      port    = params[:port]   || 8125
      @prefix = params[:prefix] || 'vmpooler'
      @server = Statsd.new(host, port)
    end

    def increment(label)
      server.increment(prefix + "." + label)
    end

    def gauge(label, value)
      server.gauge(prefix + "." + label, value)
    end

    def timing(label, duration)
      server.timing(prefix + "." + label, duration)
    end
  end

  class DummyStatsd
    attr_reader :server, :port, :prefix

    def initialize(params = {})
    end

    def increment(label)
      true
    end

    def gauge(label, value)
      true
    end

    def timing(label, duration)
      true
    end
  end
end
