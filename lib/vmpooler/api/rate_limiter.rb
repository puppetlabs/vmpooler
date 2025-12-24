# frozen_string_literal: true

module Vmpooler
  class API
    # Rate limiter middleware to protect against abuse
    # Uses Redis to track request counts per IP and token
    class RateLimiter
      DEFAULT_LIMITS = {
        global_per_ip: { limit: 100, period: 60 }, # 100 requests per minute per IP
        authenticated: { limit: 500, period: 60 }, # 500 requests per minute with token
        vm_creation: { limit: 20, period: 60 },    # 20 VM creations per minute
        vm_deletion: { limit: 50, period: 60 }     # 50 VM deletions per minute
      }.freeze

      def initialize(app, redis, config = {})
        @app = app
        @redis = redis
        @config = DEFAULT_LIMITS.merge(config[:rate_limits] || {})
        @enabled = config.fetch(:rate_limiting_enabled, true)
      end

      def call(env)
        return @app.call(env) unless @enabled

        request = Rack::Request.new(env)
        client_id = identify_client(request)
        endpoint_type = classify_endpoint(request)

        # Check rate limits
        return rate_limit_response(client_id, endpoint_type) if rate_limit_exceeded?(client_id, endpoint_type, request)

        # Track the request
        increment_request_count(client_id, endpoint_type)

        @app.call(env)
      end

      private

      def identify_client(request)
        # Prioritize token-based identification for authenticated requests
        token = request.env['HTTP_X_AUTH_TOKEN']
        return "token:#{token}" if token && !token.empty?

        # Fall back to IP address
        ip = request.ip || request.env['REMOTE_ADDR'] || 'unknown'
        "ip:#{ip}"
      end

      def classify_endpoint(request)
        path = request.path
        method = request.request_method

        return :vm_creation if method == 'POST' && path.include?('/vm')
        return :vm_deletion if method == 'DELETE' && path.include?('/vm')
        return :authenticated if request.env['HTTP_X_AUTH_TOKEN']

        :global_per_ip
      end

      def rate_limit_exceeded?(client_id, endpoint_type, _request)
        limit_config = @config[endpoint_type] || @config[:global_per_ip]
        key = "vmpooler__ratelimit__#{endpoint_type}__#{client_id}"

        current_count = @redis.get(key).to_i
        current_count >= limit_config[:limit]
      rescue StandardError => e
        # If Redis fails, allow the request through (fail open)
        warn "Rate limiter Redis error: #{e.message}"
        false
      end

      def increment_request_count(client_id, endpoint_type)
        limit_config = @config[endpoint_type] || @config[:global_per_ip]
        key = "vmpooler__ratelimit__#{endpoint_type}__#{client_id}"

        @redis.pipelined do |pipeline|
          pipeline.incr(key)
          pipeline.expire(key, limit_config[:period])
        end
      rescue StandardError => e
        # Log error but don't fail the request
        warn "Rate limiter increment error: #{e.message}"
      end

      def rate_limit_response(client_id, endpoint_type)
        limit_config = @config[endpoint_type] || @config[:global_per_ip]
        key = "vmpooler__ratelimit__#{endpoint_type}__#{client_id}"

        begin
          ttl = @redis.ttl(key)
        rescue StandardError
          ttl = limit_config[:period]
        end

        headers = {
          'Content-Type' => 'application/json',
          'X-RateLimit-Limit' => limit_config[:limit].to_s,
          'X-RateLimit-Remaining' => '0',
          'X-RateLimit-Reset' => (Time.now.to_i + ttl).to_s,
          'Retry-After' => ttl.to_s
        }

        body = JSON.pretty_generate({
                                      'ok' => false,
                                      'error' => 'Rate limit exceeded',
                                      'limit' => limit_config[:limit],
                                      'period' => limit_config[:period],
                                      'retry_after' => ttl
                                    })

        [429, headers, [body]]
      end
    end
  end
end
