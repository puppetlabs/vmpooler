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
    end
  end
end
