# frozen_string_literal: true

module Vmpooler
  # Adaptive timeout that adjusts based on observed connection performance
  # to optimize between responsiveness and reliability.
  #
  # Tracks recent connection durations and adjusts timeout to p95 + buffer,
  # reducing timeout on failures to fail faster during outages.
  class AdaptiveTimeout
    attr_reader :current_timeout

    # Initialize adaptive timeout
    #
    # @param name [String] Name for logging (e.g., "vsphere_connections")
    # @param logger [Object] Logger instance
    # @param metrics [Object] Metrics instance
    # @param min [Integer] Minimum timeout in seconds
    # @param max [Integer] Maximum timeout in seconds
    # @param initial [Integer] Initial timeout in seconds
    # @param max_samples [Integer] Number of recent samples to track
    def initialize(name:, logger:, metrics:, min: 5, max: 60, initial: 30, max_samples: 100)
      @name = name
      @logger = logger
      @metrics = metrics
      @min_timeout = min
      @max_timeout = max
      @current_timeout = initial
      @recent_durations = []
      @max_samples = max_samples
      @mutex = Mutex.new
    end

    # Get current timeout value (thread-safe)
    # @return [Integer] Current timeout in seconds
    def timeout
      @mutex.synchronize { @current_timeout }
    end

    # Record a successful operation duration
    # @param duration [Float] Duration in seconds
    def record_success(duration)
      @mutex.synchronize do
        @recent_durations << duration
        @recent_durations.shift if @recent_durations.size > @max_samples

        # Adjust timeout based on recent performance
        adjust_timeout if @recent_durations.size >= 10
      end
    end

    # Record a failure (timeout or error)
    # Reduces current timeout to fail faster on subsequent attempts
    def record_failure
      @mutex.synchronize do
        old_timeout = @current_timeout
        # Reduce timeout by 20% on failure, but don't go below minimum
        @current_timeout = [(@current_timeout * 0.8).round, @min_timeout].max

        if old_timeout != @current_timeout
          @logger.log('d', "[*] [adaptive_timeout] '#{@name}' reduced timeout #{old_timeout}s → #{@current_timeout}s after failure")
          @metrics.gauge("adaptive_timeout.current.#{@name}", @current_timeout)
        end
      end
    end

    # Reset to initial timeout (useful after recovery)
    def reset
      @mutex.synchronize do
        @recent_durations.clear
        old_timeout = @current_timeout
        @current_timeout = [@max_timeout, 30].min

        @logger.log('d', "[*] [adaptive_timeout] '#{@name}' reset timeout #{old_timeout}s → #{@current_timeout}s")
        @metrics.gauge("adaptive_timeout.current.#{@name}", @current_timeout)
      end
    end

    # Get statistics about recent durations
    # @return [Hash] Statistics including min, max, avg, p95
    def stats
      @mutex.synchronize do
        return { samples: 0 } if @recent_durations.empty?

        sorted = @recent_durations.sort
        {
          samples: sorted.size,
          min: sorted.first.round(2),
          max: sorted.last.round(2),
          avg: (sorted.sum / sorted.size.to_f).round(2),
          p50: percentile(sorted, 0.50).round(2),
          p95: percentile(sorted, 0.95).round(2),
          p99: percentile(sorted, 0.99).round(2),
          current_timeout: @current_timeout
        }
      end
    end

    private

    def adjust_timeout
      return if @recent_durations.empty?

      sorted = @recent_durations.sort
      p95_duration = percentile(sorted, 0.95)

      # Set timeout to p95 + 50% buffer, bounded by min/max
      new_timeout = (p95_duration * 1.5).round
      new_timeout = [[new_timeout, @min_timeout].max, @max_timeout].min

      # Only adjust if change is significant (> 5 seconds)
      if (new_timeout - @current_timeout).abs > 5
        old_timeout = @current_timeout
        @current_timeout = new_timeout

        @logger.log('d', "[*] [adaptive_timeout] '#{@name}' adjusted timeout #{old_timeout}s → #{@current_timeout}s (p95: #{p95_duration.round(2)}s)")
        @metrics.gauge("adaptive_timeout.current.#{@name}", @current_timeout)
        @metrics.gauge("adaptive_timeout.p95.#{@name}", p95_duration)
      end
    end

    def percentile(sorted_array, percentile)
      return 0 if sorted_array.empty?

      index = (sorted_array.size * percentile).ceil - 1
      index = [index, 0].max
      index = [index, sorted_array.size - 1].min
      sorted_array[index]
    end
  end
end
