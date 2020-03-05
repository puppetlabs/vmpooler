# frozen_string_literal: true

module Vmpooler
  class DummyStatsd
    attr_reader :server, :port, :prefix

    def initialize(*)
    end

    def increment(*)
      true
    end

    def gauge(*)
      true
    end

    def timing(*)
      true
    end
  end
end
