# frozen_string_literal: true

module Vmpooler
  class API
    # Input validation helpers to enhance security
    module InputValidator
      # Maximum lengths to prevent abuse
      MAX_HOSTNAME_LENGTH = 253
      MAX_TAG_KEY_LENGTH = 50
      MAX_TAG_VALUE_LENGTH = 255
      MAX_REASON_LENGTH = 500
      MAX_POOL_NAME_LENGTH = 100
      MAX_TOKEN_LENGTH = 64

      # Valid patterns
      HOSTNAME_PATTERN = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)* \z/ix.freeze
      POOL_NAME_PATTERN = /\A[a-zA-Z0-9_-]+\z/.freeze
      TAG_KEY_PATTERN = /\A[a-zA-Z0-9_\-.]+\z/.freeze
      TOKEN_PATTERN = /\A[a-zA-Z0-9\-_]+\z/.freeze
      INTEGER_PATTERN = /\A\d+\z/.freeze

      class ValidationError < StandardError; end

      # Validate hostname format and length
      def validate_hostname(hostname)
        return error_response('Hostname is required') if hostname.nil? || hostname.empty?
        return error_response('Hostname too long') if hostname.length > MAX_HOSTNAME_LENGTH
        return error_response('Invalid hostname format') unless hostname.match?(HOSTNAME_PATTERN)

        true
      end

      # Validate pool/template name
      def validate_pool_name(pool_name)
        return error_response('Pool name is required') if pool_name.nil? || pool_name.empty?
        return error_response('Pool name too long') if pool_name.length > MAX_POOL_NAME_LENGTH
        return error_response('Invalid pool name format') unless pool_name.match?(POOL_NAME_PATTERN)

        true
      end

      # Validate tag key and value
      def validate_tag(key, value)
        return error_response('Tag key is required') if key.nil? || key.empty?
        return error_response('Tag key too long') if key.length > MAX_TAG_KEY_LENGTH
        return error_response('Invalid tag key format') unless key.match?(TAG_KEY_PATTERN)

        if value
          return error_response('Tag value too long') if value.length > MAX_TAG_VALUE_LENGTH

          # Sanitize value to prevent injection attacks
          sanitized_value = value.gsub(/[^\w\s\-.@:\/]/, '')
          return error_response('Tag value contains invalid characters') if sanitized_value != value
        end

        true
      end

      # Validate token format
      def validate_token_format(token)
        return error_response('Token is required') if token.nil? || token.empty?
        return error_response('Token too long') if token.length > MAX_TOKEN_LENGTH
        return error_response('Invalid token format') unless token.match?(TOKEN_PATTERN)

        true
      end

      # Validate integer parameter
      def validate_integer(value, name = 'value', min: nil, max: nil)
        return error_response("#{name} is required") if value.nil?

        value_str = value.to_s
        return error_response("#{name} must be a valid integer") unless value_str.match?(INTEGER_PATTERN)

        int_value = value.to_i
        return error_response("#{name} must be at least #{min}") if min && int_value < min
        return error_response("#{name} must be at most #{max}") if max && int_value > max

        int_value
      end

      # Validate VM request count
      def validate_vm_count(count)
        validated = validate_integer(count, 'VM count', min: 1, max: 100)
        return validated if validated.is_a?(Hash) # error response

        validated
      end

      # Validate disk size
      def validate_disk_size(size)
        validated = validate_integer(size, 'Disk size', min: 1, max: 2048)
        return validated if validated.is_a?(Hash) # error response

        validated
      end

      # Validate lifetime (TTL) in hours
      def validate_lifetime(lifetime)
        validated = validate_integer(lifetime, 'Lifetime', min: 1, max: 168) # max 1 week
        return validated if validated.is_a?(Hash) # error response

        validated
      end

      # Validate reason text
      def validate_reason(reason)
        return true if reason.nil? || reason.empty?
        return error_response('Reason too long') if reason.length > MAX_REASON_LENGTH

        # Sanitize to prevent XSS/injection
        sanitized = reason.gsub(/[<>"']/, '')
        return error_response('Reason contains invalid characters') if sanitized != reason

        true
      end

      # Sanitize JSON body to prevent injection
      def sanitize_json_body(body)
        return {} if body.nil? || body.empty?

        begin
          parsed = JSON.parse(body)
          return error_response('Request body must be a JSON object') unless parsed.is_a?(Hash)

          # Limit depth and size to prevent DoS
          return error_response('Request body too complex') if json_depth(parsed) > 5
          return error_response('Request body too large') if body.length > 10_240 # 10KB max

          parsed
        rescue JSON::ParserError => e
          error_response("Invalid JSON: #{e.message}")
        end
      end

      # Check if validation result is an error
      def validation_error?(result)
        result.is_a?(Hash) && result['ok'] == false
      end

      private

      def error_response(message)
        { 'ok' => false, 'error' => message }
      end

      def json_depth(obj, depth = 0)
        return depth unless obj.is_a?(Hash) || obj.is_a?(Array)
        return depth + 1 if obj.empty?

        if obj.is_a?(Hash)
          depth + 1 + obj.values.map { |v| json_depth(v, 0) }.max
        else
          depth + 1 + obj.map { |v| json_depth(v, 0) }.max
        end
      end
    end
  end
end
