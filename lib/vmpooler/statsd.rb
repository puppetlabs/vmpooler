require 'rubygems' unless defined?(Gem)

module Vmpooler
  class Statsd
    def initialize(
      s = 'statsd',
      port = 8125
    )
      @server = Statsd.new s, port
    end
  end
end
