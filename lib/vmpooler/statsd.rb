require 'rubygems' unless defined?(Gem)

module Vmpooler
  class Statsd
    def initialize(server = 'statsd', port = 8125)
      @server = Statsd.new(server, port)
    end
  end
end
