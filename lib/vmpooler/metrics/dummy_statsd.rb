# frozen_string_literal: true

module Vmpooler
  class Metrics
    class DummyStatsd < Metrics
      attr_reader :server, :port, :prefix

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
end
