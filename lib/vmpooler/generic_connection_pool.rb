require 'connection_pool'

module Vmpooler
  class PoolManager
    class GenericConnectionPool < ConnectionPool
      # Extend the ConnectionPool class with instrumentation
      # https://github.com/mperham/connection_pool/blob/master/lib/connection_pool.rb

      def initialize(options = {}, &block)
        super(options, &block)
        @metrics = options[:metrics]
        @metric_prefix = options[:metric_prefix]
        @metric_prefix = 'connectionpool' if @metric_prefix.nil? || @metric_prefix == ''
      end

      if Thread.respond_to?(:handle_interrupt)
        # MRI
        def with_metrics(options = {})
          Thread.handle_interrupt(Exception => :never) do
            start = Time.now
            conn = checkout(options)
            timespan_ms = ((Time.now - start) * 1000).to_i
            @metrics&.gauge(@metric_prefix + '.available', @available.length)
            @metrics&.timing(@metric_prefix + '.waited', timespan_ms)
            begin
              Thread.handle_interrupt(Exception => :immediate) do
                yield conn
              end
            ensure
              checkin
              @metrics&.gauge(@metric_prefix + '.available', @available.length)
            end
          end
        end
      else
        # jruby 1.7.x
        def with_metrics(options = {})
          start = Time.now
          conn = checkout(options)
          timespan_ms = ((Time.now - start) * 1000).to_i
          @metrics&.gauge(@metric_prefix + '.available', @available.length)
          @metrics&.timing(@metric_prefix + '.waited', timespan_ms)
          begin
            yield conn
          ensure
            checkin
            @metrics&.gauge(@metric_prefix + '.available', @available.length)
          end
        end
      end
    end
  end
end
