# frozen_string_literal: true

module Vmpooler
  class PoolManager
    # Auto-scaling module for dynamically adjusting pool sizes based on demand
    class AutoScaler
      attr_reader :logger, :redis, :metrics

      def initialize(redis_connection_pool, logger, metrics)
        @redis = redis_connection_pool
        @logger = logger
        @metrics = metrics
        @last_scale_time = Concurrent::Hash.new
      end

      # Check if auto-scaling is enabled for a pool
      def enabled_for_pool?(pool)
        return false unless pool['auto_scale']
        return false unless pool['auto_scale']['enabled'] == true

        true
      end

      # Calculate the target pool size based on current metrics
      def calculate_target_size(pool, pool_name)
        auto_scale_config = pool['auto_scale']
        min_size = auto_scale_config['min_size'] || pool['size']
        max_size = auto_scale_config['max_size'] || pool['size'] * 5
        scale_up_threshold = auto_scale_config['scale_up_threshold'] || 20
        scale_down_threshold = auto_scale_config['scale_down_threshold'] || 80
        cooldown_period = auto_scale_config['cooldown_period'] || 300

        # Check cooldown period
        last_scale = @last_scale_time[pool_name]
        if last_scale && (Time.now - last_scale) < cooldown_period
          logger.log('d', "[~] [#{pool_name}] Auto-scaling in cooldown period (#{cooldown_period}s)")
          return pool['size']
        end

        # Get current pool metrics
        pool_metrics = get_pool_metrics(pool_name)
        current_size = pool['size']
        ready_count = pool_metrics[:ready]
        running_count = pool_metrics[:running]
        pending_count = pool_metrics[:pending]

        # Calculate total VMs (ready + running + pending)
        total_vms = ready_count + running_count + pending_count
        total_vms = 1 if total_vms == 0 # Avoid division by zero

        # Calculate ready percentage
        ready_percentage = (ready_count.to_f / total_vms * 100).round(2)

        logger.log('d', "[~] [#{pool_name}] Metrics: ready=#{ready_count}, running=#{running_count}, pending=#{pending_count}, ready%=#{ready_percentage}")

        # Determine if we need to scale
        if ready_percentage < scale_up_threshold
          # Scale up: increase pool size
          new_size = calculate_scale_up_size(current_size, max_size, ready_percentage, scale_up_threshold)
          if new_size > current_size
            logger.log('s', "[+] [#{pool_name}] Scaling UP: #{current_size} -> #{new_size} (ready: #{ready_percentage}% < #{scale_up_threshold}%)")
            @last_scale_time[pool_name] = Time.now
            @metrics.increment("scale_up.#{pool_name}")
            return new_size
          end
        elsif ready_percentage > scale_down_threshold
          # Scale down: decrease pool size (only if no pending requests)
          pending_requests = get_pending_requests_count(pool_name)
          if pending_requests == 0
            new_size = calculate_scale_down_size(current_size, min_size, ready_percentage, scale_down_threshold)
            if new_size < current_size
              logger.log('s', "[-] [#{pool_name}] Scaling DOWN: #{current_size} -> #{new_size} (ready: #{ready_percentage}% > #{scale_down_threshold}%)")
              @last_scale_time[pool_name] = Time.now
              @metrics.increment("scale_down.#{pool_name}")
              return new_size
            end
          else
            logger.log('d', "[~] [#{pool_name}] Not scaling down: #{pending_requests} pending requests")
          end
        end

        current_size
      end

      # Get current pool metrics from Redis
      def get_pool_metrics(pool_name)
        @redis.with do |redis|
          {
            ready: redis.llen("vmpooler__ready__#{pool_name}") || 0,
            running: redis.scard("vmpooler__running__#{pool_name}") || 0,
            pending: redis.llen("vmpooler__pending__#{pool_name}") || 0
          }
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

          pending_count
        end
      end

      # Calculate new size when scaling up
      def calculate_scale_up_size(current_size, max_size, ready_percentage, threshold)
        # Aggressive scaling when very low on ready VMs
        if ready_percentage < threshold / 2
          # Double the size or add 10, whichever is larger
          new_size = [current_size * 2, current_size + 10].max
        else
          # Moderate scaling: increase by 50%
          new_size = (current_size * 1.5).ceil
        end

        [new_size, max_size].min
      end

      # Calculate new size when scaling down
      def calculate_scale_down_size(current_size, min_size, _ready_percentage, _threshold)
        # Conservative scaling down: only reduce by 25%
        new_size = (current_size * 0.75).floor

        [new_size, min_size].max
      end

      # Apply auto-scaling to a pool
      def apply_auto_scaling(pool)
        return unless enabled_for_pool?(pool)

        pool_name = pool['name']
        target_size = calculate_target_size(pool, pool_name)

        if target_size != pool['size']
          pool['size'] = target_size
          update_pool_size_in_redis(pool_name, target_size)
        end
      rescue StandardError => e
        logger.log('s', "[!] [#{pool_name}] Auto-scaling error: #{e.message}")
        logger.log('s', e.backtrace.join("\n")) if logger.respond_to?(:level) && logger.level == 'debug'
      end

      # Update pool size in Redis
      def update_pool_size_in_redis(pool_name, new_size)
        @redis.with do |redis|
          redis.hset("vmpooler__pool__#{pool_name}", 'size', new_size)
        end
      end
    end
  end
end
