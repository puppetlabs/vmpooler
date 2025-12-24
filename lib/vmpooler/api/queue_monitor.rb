# frozen_string_literal: true

require 'vmpooler/api'

module Vmpooler
  class API
    # Queue monitoring endpoint for tracking pool queue depths and health
    class QueueMonitor < Sinatra::Base
      api_version = '1'
      api_prefix  = "/api/v#{api_version}"

      helpers do
        include Vmpooler::API::Helpers
      end

      # Get queue status for all pools or a specific pool
      get "#{api_prefix}/queue/status/?" do
        content_type :json

        result = {
          ok: true,
          timestamp: Time.now.to_i,
          pools: {}
        }

        pool_filter = params[:pool]

        pools = pool_filter ? [pool_filter] : list_pools

        pools.each do |pool_name|
          begin
            metrics = get_queue_metrics(pool_name)
            result[:pools][pool_name] = metrics
          rescue StandardError => e
            result[:pools][pool_name] = {
              error: e.message
            }
          end
        end

        JSON.pretty_generate(result)
      end

      # Get detailed queue metrics for a specific pool
      get "#{api_prefix}/queue/status/:pool/?" do
        content_type :json

        pool_name = params[:pool]

        unless pool_exists?(pool_name)
          halt 404, JSON.pretty_generate({
                                           ok: false,
                                           error: "Pool '#{pool_name}' not found"
                                         })
        end

        begin
          metrics = get_queue_metrics(pool_name)
          result = {
            ok: true,
            timestamp: Time.now.to_i,
            pool: pool_name,
            metrics: metrics
          }

          JSON.pretty_generate(result)
        rescue StandardError => e
          status 500
          JSON.pretty_generate({
                                 ok: false,
                                 error: e.message
                               })
        end
      end

      # Helper method to get queue metrics for a pool
      def get_queue_metrics(pool_name)
        redis = redis_connection_pool

        metrics = redis.with_metrics do |conn|
          {
            ready: conn.llen("vmpooler__ready__#{pool_name}") || 0,
            running: conn.scard("vmpooler__running__#{pool_name}") || 0,
            pending: conn.llen("vmpooler__pending__#{pool_name}") || 0
          }
        end

        # Get pending requests count
        pending_requests = get_pending_requests_for_pool(pool_name, redis)

        # Get oldest pending request age
        oldest_pending = get_oldest_pending_request(pool_name, redis)

        # Get pool configuration
        pool_config = get_pool_config(pool_name, redis)

        # Calculate health metrics
        total_vms = metrics[:ready] + metrics[:running] + metrics[:pending]
        ready_percentage = total_vms > 0 ? (metrics[:ready].to_f / total_vms * 100).round(2) : 0
        capacity_percentage = pool_config[:size] > 0 ? ((metrics[:ready] + metrics[:pending]).to_f / pool_config[:size] * 100).round(2) : 0

        # Determine health status
        health_status = determine_health_status(metrics, pending_requests, pool_config)

        {
          ready: metrics[:ready],
          running: metrics[:running],
          pending: metrics[:pending],
          total: total_vms,
          pending_requests: pending_requests,
          oldest_pending_age_seconds: oldest_pending,
          pool_size: pool_config[:size],
          ready_percentage: ready_percentage,
          capacity_percentage: capacity_percentage,
          health: health_status
        }
      end

      # Get pending requests count for a pool
      def get_pending_requests_for_pool(pool_name, redis)
        redis.with_metrics do |conn|
          request_keys = conn.keys('vmpooler__request__*')
          pending_count = 0

          request_keys.each do |key|
            request_data = conn.hgetall(key)
            pending_count += request_data[pool_name].to_i if request_data['status'] == 'pending' && request_data.key?(pool_name)
          end

          pending_count
        end
      end

      # Get age of oldest pending request in seconds
      def get_oldest_pending_request(pool_name, redis)
        redis.with_metrics do |conn|
          request_keys = conn.keys('vmpooler__request__*')
          oldest_timestamp = nil

          request_keys.each do |key|
            request_data = conn.hgetall(key)
            if request_data['status'] == 'pending' && request_data.key?(pool_name)
              requested_at = request_data['requested_at']&.to_i
              oldest_timestamp = requested_at if requested_at && (oldest_timestamp.nil? || requested_at < oldest_timestamp)
            end
          end

          oldest_timestamp ? Time.now.to_i - oldest_timestamp : 0
        end
      end

      # Get pool configuration from Redis
      def get_pool_config(pool_name, redis)
        redis.with_metrics do |conn|
          config = conn.hgetall("vmpooler__pool__#{pool_name}")
          {
            size: config['size']&.to_i || 0,
            template: config['template'] || 'unknown'
          }
        end
      end

      # Determine health status based on metrics
      def determine_health_status(metrics, pending_requests, pool_config)
        if metrics[:ready] == 0 && pending_requests > 0
          'critical' # No ready VMs and users are waiting
        elsif metrics[:ready] == 0 && metrics[:pending] > 0
          'warning' # No ready VMs but some are being created
        elsif metrics[:ready] < (pool_config[:size] * 0.2).ceil
          'warning' # Less than 20% ready VMs
        elsif pending_requests > 0
          'warning' # Users waiting for VMs
        else
          'healthy'
        end
      end

      # Check if pool exists
      def pool_exists?(pool_name)
        redis = redis_connection_pool
        redis.with_metrics do |conn|
          conn.sismember('vmpooler__pools', pool_name)
        end
      end

      # Get list of all pools
      def list_pools
        redis = redis_connection_pool
        redis.with_metrics do |conn|
          conn.smembers('vmpooler__pools') || []
        end
      end
    end
  end
end
