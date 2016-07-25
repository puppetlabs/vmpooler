module Vmpooler
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
