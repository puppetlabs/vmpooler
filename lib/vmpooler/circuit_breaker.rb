# frozen_string_literal: true

module Vmpooler
  # Circuit breaker pattern implementation to prevent cascading failures
  # when a provider becomes unresponsive or experiences repeated failures.
  #
  # States:
  # - CLOSED: Normal operation, requests flow through
  # - OPEN: Provider is failing, reject requests immediately (fail fast)
  # - HALF_OPEN: Testing if provider has recovered with limited requests
  class CircuitBreaker
    STATES = [:closed, :open, :half_open].freeze

    class CircuitOpenError < StandardError; end

    attr_reader :state, :failure_count, :success_count

    # Initialize a new circuit breaker
    #
    # @param name [String] Name for logging/metrics (e.g., "vsphere_provider")
    # @param logger [Object] Logger instance
    # @param metrics [Object] Metrics instance
    # @param failure_threshold [Integer] Number of failures before opening circuit
    # @param timeout [Integer] Seconds to wait in open state before testing (half-open)
    # @param half_open_attempts [Integer] Number of successful test requests needed to close
    def initialize(name:, logger:, metrics:, failure_threshold: 5, timeout: 30, half_open_attempts: 3)
      @name = name
      @logger = logger
      @metrics = metrics
      @failure_threshold = failure_threshold
      @timeout = timeout
      @half_open_attempts = half_open_attempts

      @state = :closed
      @failure_count = 0
      @success_count = 0
      @last_failure_time = nil
      @mutex = Mutex.new
    end

    # Execute a block with circuit breaker protection
    #
    # @yield Block to execute if circuit allows
    # @return Result of the block
    # @raise CircuitOpenError if circuit is open and timeout hasn't elapsed
    def call
      check_state

      begin
        result = yield
        on_success
        result
      rescue StandardError => e
        on_failure(e)
        raise
      end
    end

    # Check if circuit allows requests
    # @return [Boolean] true if circuit is closed or half-open
    def allow_request?
      @mutex.synchronize do
        case @state
        when :closed
          true
        when :half_open
          true
        when :open
          if should_attempt_reset?
            true
          else
            false
          end
        end
      end
    end

    # Get current circuit breaker status
    # @return [Hash] Status information
    def status
      @mutex.synchronize do
        {
          name: @name,
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          last_failure_time: @last_failure_time,
          next_retry_time: next_retry_time
        }
      end
    end

    private

    def check_state
      @mutex.synchronize do
        case @state
        when :open
          if should_attempt_reset?
            transition_to_half_open
          else
            time_remaining = (@timeout - (Time.now - @last_failure_time)).round(1)
            raise CircuitOpenError, "Circuit breaker '#{@name}' is open (#{@failure_count} failures, retry in #{time_remaining}s)"
          end
        when :half_open
          # Allow limited requests through for testing
        when :closed
          # Normal operation
        end
      end
    end

    def should_attempt_reset?
      return false unless @last_failure_time

      Time.now - @last_failure_time >= @timeout
    end

    def next_retry_time
      return nil unless @last_failure_time && @state == :open

      @last_failure_time + @timeout
    end

    def on_success
      @mutex.synchronize do
        case @state
        when :closed
          # Reset failure count on success in closed state
          @failure_count = 0 if @failure_count > 0
        when :half_open
          @success_count += 1
          @failure_count = 0
          @logger.log('d', "[+] [circuit_breaker] '#{@name}' successful test request (#{@success_count}/#{@half_open_attempts})")

          if @success_count >= @half_open_attempts
            transition_to_closed
          end
        when :open
          # Should not happen, but reset if we somehow get a success
          transition_to_closed
        end
      end
    end

    def on_failure(error)
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.now

        case @state
        when :closed
          @logger.log('d', "[!] [circuit_breaker] '#{@name}' failure #{@failure_count}/#{@failure_threshold}: #{error.class}")
          if @failure_count >= @failure_threshold
            transition_to_open
          end
        when :half_open
          @logger.log('d', "[!] [circuit_breaker] '#{@name}' failed during half-open test")
          transition_to_open
        when :open
          # Already open, just log
          @logger.log('d', "[!] [circuit_breaker] '#{@name}' additional failure while open")
        end
      end
    end

    def transition_to_open
      @state = :open
      @success_count = 0
      @logger.log('s', "[!] [circuit_breaker] '#{@name}' OPENED after #{@failure_count} failures (will retry in #{@timeout}s)")
      @metrics.increment("circuit_breaker.opened.#{@name}")
      @metrics.gauge("circuit_breaker.state.#{@name}", 1) # 1 = open
    end

    def transition_to_half_open
      @state = :half_open
      @success_count = 0
      @failure_count = 0
      @logger.log('s', "[*] [circuit_breaker] '#{@name}' HALF-OPEN, testing provider health")
      @metrics.increment("circuit_breaker.half_open.#{@name}")
      @metrics.gauge("circuit_breaker.state.#{@name}", 0.5) # 0.5 = half-open
    end

    def transition_to_closed
      @state = :closed
      @failure_count = 0
      @success_count = 0
      @logger.log('s', "[+] [circuit_breaker] '#{@name}' CLOSED, provider recovered")
      @metrics.increment("circuit_breaker.closed.#{@name}")
      @metrics.gauge("circuit_breaker.state.#{@name}", 0) # 0 = closed
    end
  end
end
