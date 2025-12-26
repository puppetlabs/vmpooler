# frozen_string_literal: true

require 'connection_pool'

module Vmpooler
  class PoolManager
    class GenericConnectionPool < ConnectionPool
      # Extend the ConnectionPool class with instrumentation
      # https://github.com/mperham/connection_pool/blob/master/lib/connection_pool.rb

      def initialize(options = {}, &block)
        super(options, &block)
        @metrics = options[:metrics]
        @connpool_type = options[:connpool_type]
        @connpool_type = 'connectionpool' if @connpool_type.nil? || @connpool_type == ''
        @connpool_provider = options[:connpool_provider]
        @connpool_provider = 'unknown' if @connpool_provider.nil? || @connpool_provider == ''
      end

      def with_metrics(options = {})
        Thread.handle_interrupt(Exception => :never) do
          start = Time.now
          conn = checkout(options)
          timespan_ms = ((Time.now - start) * 1000).to_i
          @metrics&.gauge("connection_available.#{@connpool_type}.#{@connpool_provider}", @available.length)
          @metrics&.timing("connection_waited.#{@connpool_type}.#{@connpool_provider}", timespan_ms)
          begin
            Thread.handle_interrupt(Exception => :immediate) do
              yield conn
            end
          ensure
            checkin
            @metrics&.gauge("connection_available.#{@connpool_type}.#{@connpool_provider}", @available.length)
          end
        end
      end

      # Get connection pool health status
      # @return [Hash] Health status including utilization and queue depth
      def health_status
        {
          size: @size,
          available: @available.length,
          in_use: @size - @available.length,
          utilization: ((@size - @available.length).to_f / @size * 100).round(2),
          waiting_threads: (@queue.respond_to?(:length) ? @queue.length : 0),
          state: determine_health_state
        }
      end

      private

      def determine_health_state
        utilization = ((@size - @available.length).to_f / @size * 100)
        waiting = @queue.respond_to?(:length) ? @queue.length : 0

        if utilization >= 90 || waiting > 5
          :critical  # Pool exhausted or many waiting threads
        elsif utilization >= 70 || waiting > 2
          :warning   # Pool under stress
        else
          :healthy   # Normal operation
        end
      end
    end
  end
end
