# frozen_string_literal: true

module Vmpooler
  class PoolManager
    # Rate-based provisioning for adjusting clone concurrency based on demand
    class RateProvisioner
      attr_reader :logger, :redis, :metrics

      def initialize(redis_connection_pool, logger, metrics)
        @redis = redis_connection_pool
        @logger = logger
        @metrics = metrics
        @current_mode = Concurrent::Hash.new # Track provisioning mode per pool
      end

      # Check if rate-based provisioning is enabled for a pool
      def enabled_for_pool?(pool)
        return false unless pool['rate_provisioning']
        return false unless pool['rate_provisioning']['enabled'] == true

        true
      end

      # Get the appropriate clone concurrency based on current demand
      def get_clone_concurrency(pool, pool_name)
        return pool['clone_target_concurrency'] || 2 unless enabled_for_pool?(pool)

        rate_config = pool['rate_provisioning']
        normal_concurrency = rate_config['normal_concurrency'] || 2
        high_demand_concurrency = rate_config['high_demand_concurrency'] || 5
        threshold = rate_config['queue_depth_threshold'] || 5

        # Get current queue metrics
        ready_count = get_ready_count(pool_name)
        pending_requests = get_pending_requests_count(pool_name)

        # Determine if we're in high-demand mode
        # High demand = many pending requests OR very few ready VMs
        high_demand = (pending_requests >= threshold) || (ready_count == 0 && pending_requests > 0)

        new_mode = high_demand ? :high_demand : :normal
        old_mode = @current_mode[pool_name] || :normal

        # Log mode changes
        if new_mode != old_mode
          concurrency = new_mode == :high_demand ? high_demand_concurrency : normal_concurrency
          logger.log('s', "[~] [#{pool_name}] Provisioning mode: #{old_mode} -> #{new_mode} (concurrency: #{concurrency}, pending: #{pending_requests}, ready: #{ready_count})")
          @current_mode[pool_name] = new_mode
          metrics.increment("provisioning_mode_change.#{pool_name}.#{new_mode}")
        end

        new_mode == :high_demand ? high_demand_concurrency : normal_concurrency
      end

      # Get count of ready VMs
      def get_ready_count(pool_name)
        @redis.with do |redis|
          redis.llen("vmpooler__ready__#{pool_name}") || 0
        end
      end

      # Get count of pending VM requests
      def get_pending_requests_count(pool_name)
        @redis.with do |redis|
          # Check for pending requests in request queue
          request_keys = redis.keys('vmpooler__request__*')
          pending_count = 0

          request_keys.each do |key|
            request_data = redis.hgetall(key)
            pending_count += request_data[pool_name].to_i if request_data['status'] == 'pending' && request_data.key?(pool_name)
          end

          # Also check the queue itself for waiting allocations
          queue_depth = redis.llen("vmpooler__pending__#{pool_name}") || 0

          [pending_count, queue_depth].max
        end
      end

      # Get current provisioning mode for a pool
      def get_current_mode(pool_name)
        @current_mode[pool_name] || :normal
      end

      # Force reset to normal mode (useful for testing or recovery)
      def reset_to_normal(pool_name)
        @current_mode[pool_name] = :normal
        logger.log('d', "[~] [#{pool_name}] Provisioning mode reset to normal")
      end
    end
  end
end
