# frozen_string_literal: true

require 'vmpooler/dns'
require 'vmpooler/providers'
require 'vmpooler/util/parsing'
require 'spicy-proton'
require 'resolv' # ruby standard lib

module Vmpooler
  class PoolManager
    CHECK_LOOP_DELAY_MIN_DEFAULT = 5
    CHECK_LOOP_DELAY_MAX_DEFAULT = 60
    CHECK_LOOP_DELAY_DECAY_DEFAULT = 2.0

    def initialize(config, logger, redis_connection_pool, metrics)
      $config = config

      # Load logger library
      $logger = logger

      # metrics logging handle
      $metrics = metrics

      # Redis connection pool
      @redis = redis_connection_pool

      # VM Provider objects
      $providers = Concurrent::Hash.new

      # VM DNS objects
      $dns_plugins = Concurrent::Hash.new

      # Our thread-tracker object
      $threads = Concurrent::Hash.new

      # Pool mutex
      @reconfigure_pool = Concurrent::Hash.new

      @vm_mutex = Concurrent::Hash.new

      # Name generator for generating host names
      @name_generator = Spicy::Proton.new

      # load specified providers from config file
      load_used_providers

      # load specified dns plugins from config file
      load_used_dns_plugins
    end

    def config
      $config
    end

    # Place pool configuration in redis so an API instance can discover running pool configuration
    def load_pools_to_redis
      @redis.with_metrics do |redis|
        previously_configured_pools = redis.smembers('vmpooler__pools')
        currently_configured_pools = []
        config[:pools].each do |pool|
          currently_configured_pools << pool['name']
          redis.sadd('vmpooler__pools', pool['name'].to_s)
          pool_keys = pool.keys
          pool_keys.delete('alias')
          to_set = {}
          pool_keys.each do |k|
            to_set[k] = pool[k]
          end
          to_set['alias'] = pool['alias'].join(',') if to_set.key?('alias')
          to_set['domain'] = Vmpooler::Dns.get_domain_for_pool(config, pool['name'])

          redis.hmset("vmpooler__pool__#{pool['name']}", *to_set.to_a.flatten) unless to_set.empty?
        end
        previously_configured_pools.each do |pool|
          unless currently_configured_pools.include? pool
            redis.srem('vmpooler__pools', pool.to_s)
            redis.del("vmpooler__pool__#{pool}")
          end
        end
      end
      nil
    end

    # Check the state of a VM
    def check_pending_vm(vm, pool, timeout, timeout_notification, provider)
      Thread.new do
        begin
          _check_pending_vm(vm, pool, timeout, timeout_notification, provider)
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool}] '#{vm}' #{timeout} #{provider} errored while checking a pending vm : #{e}")
          @redis.with_metrics do |redis|
            fail_pending_vm(vm, pool, timeout, timeout_notification, redis)
          end
          raise
        end
      end
    end

    def _check_pending_vm(vm, pool, timeout, timeout_notification, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        @redis.with_metrics do |redis|
          request_id = redis.hget("vmpooler__vm__#{vm}", 'request_id')
          if provider.vm_ready?(pool, vm, redis)
            move_pending_vm_to_ready(vm, pool, redis, request_id)
          else
            fail_pending_vm(vm, pool, timeout, timeout_notification, redis)
          end
        end
      end
    end

    def remove_nonexistent_vm(vm, pool, redis)
      redis.srem("vmpooler__pending__#{pool}", vm)
      dns_plugin = get_dns_plugin_class_for_pool(pool)
      dns_plugin_class_name = get_dns_plugin_class_name_for_pool(pool)
      domain = get_dns_plugin_domain_for_pool(pool)
      fqdn = "#{vm}.#{domain}"
      dns_plugin.delete_record(fqdn) unless dns_plugin_class_name == 'dynamic-dns'
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    def fail_pending_vm(vm, pool, timeout, timeout_notification, redis, exists: true)
      clone_stamp = redis.hget("vmpooler__vm__#{vm}", 'clone')
      time_since_clone = (Time.now - Time.parse(clone_stamp)) / 60

      already_timed_out = time_since_clone > timeout
      timing_out_soon = time_since_clone > timeout_notification && !redis.hget("vmpooler__vm__#{vm}", 'timeout_notification')

      return true if !already_timed_out && !timing_out_soon

      if already_timed_out
        unless exists
          remove_nonexistent_vm(vm, pool, redis)
          return true
        end
        open_socket_error = handle_timed_out_vm(vm, pool, redis)
      end

      redis.hset("vmpooler__vm__#{vm}", 'timeout_notification', 1) if timing_out_soon

      nonexist_warning = if already_timed_out
                           "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes with error: #{open_socket_error}"
                         elsif timing_out_soon
                           time_remaining = timeout - timeout_notification
                           open_socket_error = redis.hget("vmpooler__vm__#{vm}", 'open_socket_error')
                           "[!] [#{pool}] '#{vm}' impending failure in #{time_remaining} minutes with error: #{open_socket_error}"
                         else
                           "[!] [#{pool}] '#{vm}' This error is wholly unexpected"
                         end
      $logger.log('d', nonexist_warning)
      true
    rescue StandardError => e
      $logger.log('d', "Fail pending VM failed with an error: #{e}")
      false
    end

    def handle_timed_out_vm(vm, pool, redis)
      request_id = redis.hget("vmpooler__vm__#{vm}", 'request_id')
      pool_alias = redis.hget("vmpooler__vm__#{vm}", 'pool_alias') if request_id
      open_socket_error = redis.hget("vmpooler__vm__#{vm}", 'open_socket_error')
      retry_count = redis.hget("vmpooler__odrequest__#{request_id}", 'retry_count').to_i if request_id

      # Move to DLQ before moving to completed queue
      move_to_dlq(vm, pool, 'pending', 'Timeout',
                  open_socket_error || 'VM timed out during pending phase',
                  redis, request_id: request_id, pool_alias: pool_alias, retry_count: retry_count)

      clone_error = redis.hget("vmpooler__vm__#{vm}", 'clone_error')
      clone_error_class = redis.hget("vmpooler__vm__#{vm}", 'clone_error_class')
      redis.smove("vmpooler__pending__#{pool}", "vmpooler__completed__#{pool}", vm)

      if request_id
        ondemandrequest_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
        if ondemandrequest_hash && ondemandrequest_hash['status'] != 'failed' && ondemandrequest_hash['status'] != 'deleted'
          # Check retry count and max retry limit before retrying
          retry_count = (redis.hget("vmpooler__odrequest__#{request_id}", 'retry_count') || '0').to_i
          max_retries = $config[:config]['max_vm_retries'] || 3

          $logger.log('s', "[!] [#{pool}] '#{vm}' checking retry logic: error='#{clone_error}', error_class='#{clone_error_class}', retry_count=#{retry_count}, max_retries=#{max_retries}")

          # Determine if error is likely permanent (configuration issues)
          permanent_error = permanent_error?(clone_error, clone_error_class)
          $logger.log('s', "[!] [#{pool}] '#{vm}' permanent_error check result: #{permanent_error}")

          if retry_count < max_retries && !permanent_error
            # Increment retry count and retry VM creation
            redis.hset("vmpooler__odrequest__#{request_id}", 'retry_count', retry_count + 1)
            redis.zadd('vmpooler__odcreate__task', 1, "#{pool_alias}:#{pool}:1:#{request_id}")
            $logger.log('s', "[!] [#{pool}] '#{vm}' failed, retrying (attempt #{retry_count + 1}/#{max_retries})")
          else
            # Max retries exceeded or permanent error, mark request as permanently failed
            failure_reason = if permanent_error
                               "Configuration error: #{clone_error}"
                             else
                               'Max retry attempts exceeded'
                             end
            redis.hset("vmpooler__odrequest__#{request_id}", 'status', 'failed')
            redis.hset("vmpooler__odrequest__#{request_id}", 'failure_reason', failure_reason)
            $logger.log('s', "[!] [#{pool}] '#{vm}' permanently failed: #{failure_reason}")
            $metrics.increment("errors.permanently_failed.#{pool}")
          end
        end
      end
      $metrics.increment("errors.markedasfailed.#{pool}")
      open_socket_error || clone_error
    end

    # Determine if an error is likely permanent (configuration issue) vs transient
    def permanent_error?(error_message, error_class)
      return false if error_message.nil? || error_class.nil?

      permanent_error_patterns = [
        /template.*not found/i,
        /template.*does not exist/i,
        /invalid.*path/i,
        /folder.*not found/i,
        /datastore.*not found/i,
        /resource pool.*not found/i,
        /permission.*denied/i,
        /authentication.*failed/i,
        /invalid.*credentials/i,
        /configuration.*error/i
      ]

      permanent_error_classes = [
        'ArgumentError',
        'NoMethodError',
        'NameError'
      ]

      # Check error message patterns
      permanent_error_patterns.any? { |pattern| error_message.match?(pattern) } ||
        # Check error class types
        permanent_error_classes.include?(error_class)
    end

    def move_pending_vm_to_ready(vm, pool, redis, request_id = nil)
      clone_time = redis.hget("vmpooler__vm__#{vm}", 'clone')
      finish = format('%<time>.2f', time: Time.now - Time.parse(clone_time))

      if request_id
        ondemandrequest_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
        case ondemandrequest_hash['status']
        when 'failed'
          move_vm_queue(pool, vm, 'pending', 'completed', redis, "moved to completed queue. '#{request_id}' could not be filled in time")
          return nil
        when 'deleted'
          move_vm_queue(pool, vm, 'pending', 'completed', redis, "moved to completed queue. '#{request_id}' has been deleted")
          return nil
        end
        pool_alias = redis.hget("vmpooler__vm__#{vm}", 'pool_alias')

        redis.pipelined do |pipeline|
          pipeline.hset("vmpooler__active__#{pool}", vm, Time.now.to_s)
          pipeline.hset("vmpooler__vm__#{vm}", 'checkout', Time.now.to_s)
          if ondemandrequest_hash['token:token']
            pipeline.hset("vmpooler__vm__#{vm}", 'token:token', ondemandrequest_hash['token:token'])
            pipeline.hset("vmpooler__vm__#{vm}", 'token:user', ondemandrequest_hash['token:user'])
            pipeline.hset("vmpooler__vm__#{vm}", 'lifetime', $config[:config]['vm_lifetime_auth'].to_i)
          end
          pipeline.sadd("vmpooler__#{request_id}__#{pool_alias}__#{pool}", vm)
        end
        move_vm_queue(pool, vm, 'pending', 'running', redis)
        check_ondemand_request_ready(request_id, redis)
      else
        redis.smove("vmpooler__pending__#{pool}", "vmpooler__ready__#{pool}", vm)
      end

      redis.pipelined do |pipeline|
        pipeline.hset("vmpooler__boot__#{Date.today}", "#{pool}:#{vm}", finish) # maybe remove as this is never used by vmpooler itself?
        pipeline.hset("vmpooler__vm__#{vm}", 'ready', Time.now.to_s)

        # last boot time is displayed in API, and used by alarming script
        pipeline.hset('vmpooler__lastboot', pool, Time.now.to_s)
      end

      $metrics.timing("time_to_ready_state.#{pool}", finish)
      $logger.log('s', "[>] [#{pool}] '#{vm}' moved from 'pending' to 'ready' queue") unless request_id
      $logger.log('s', "[>] [#{pool}] '#{vm}' is 'ready' for request '#{request_id}'") if request_id
    end

    def vm_still_ready?(pool_name, vm_name, provider, redis)
      # Check if the VM is still ready/available
      return true if provider.vm_ready?(pool_name, vm_name, redis)

      raise("VM #{vm_name} is not ready")
    rescue StandardError => e
      open_socket_error = redis.hget("vmpooler__vm__#{vm_name}", 'open_socket_error')
      request_id = redis.hget("vmpooler__vm__#{vm_name}", 'request_id')
      pool_alias = redis.hget("vmpooler__vm__#{vm_name}", 'pool_alias')

      # Move to DLQ before moving to completed queue
      move_to_dlq(vm_name, pool_name, 'ready', e.class.name,
                  open_socket_error || 'VM became unreachable in ready queue',
                  redis, request_id: request_id, pool_alias: pool_alias)

      move_vm_queue(pool_name, vm_name, 'ready', 'completed', redis, "removed from 'ready' queue. vm unreachable with error: #{open_socket_error}")
    end

    def check_ready_vm(vm, pool_name, ttl, provider)
      Thread.new do
        begin
          _check_ready_vm(vm, pool_name, ttl, provider)
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool_name}] '#{vm}' failed while checking a ready vm : #{e}")
          raise
        end
      end
    end

    def _check_ready_vm(vm, pool_name, ttl, provider)
      # Periodically check that the VM is available
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        @redis.with_metrics do |redis|
          check_stamp = redis.hget("vmpooler__vm__#{vm}", 'check')
          last_checked_too_soon = ((Time.now - Time.parse(check_stamp)).to_i < $config[:config]['vm_checktime'] * 60) if check_stamp
          break if check_stamp && last_checked_too_soon

          redis.hset("vmpooler__vm__#{vm}", 'check', Time.now.to_s)
          # Check if the hosts TTL has expired
          # if 'boottime' is nil, set bootime to beginning of unix epoch, forces TTL to be assumed expired
          boottime = redis.hget("vmpooler__vm__#{vm}", 'ready')
          if boottime
            boottime = Time.parse(boottime)
          else
            boottime = Time.at(0)
          end
          if (Time.now - boottime).to_i > ttl * 60
            redis.smove("vmpooler__ready__#{pool_name}", "vmpooler__completed__#{pool_name}", vm)

            $logger.log('d', "[!] [#{pool_name}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
            return nil
          end

          break if mismatched_hostname?(vm, pool_name, provider, redis)

          vm_still_ready?(pool_name, vm, provider, redis)
        end
      end
    end

    def mismatched_hostname?(vm, pool_name, provider, redis)
      pool_config = $config[:pools][$config[:pool_index][pool_name]]
      check_hostname = pool_config['check_hostname_for_mismatch']
      check_hostname = $config[:config]['check_ready_vm_hostname_for_mismatch'] if check_hostname.nil?
      return if check_hostname == false

      # Wait one minute before checking a VM for hostname mismatch
      # When checking as soon as the VM passes the ready test the instance
      # often doesn't report its hostname yet causing the VM to be removed immediately
      vm_ready_time = redis.hget("vmpooler__vm__#{vm}", 'ready')
      if vm_ready_time
        wait_before_checking = 60
        time_since_ready = (Time.now - Time.parse(vm_ready_time)).to_i
        return unless time_since_ready > wait_before_checking
      end

      # Check if the hostname has magically changed from underneath Pooler
      vm_hash = provider.get_vm(pool_name, vm)
      return unless vm_hash.is_a? Hash

      hostname = vm_hash['hostname']

      return if hostname.nil?
      return if hostname.empty?
      return if hostname == vm

      redis.smove("vmpooler__ready__#{pool_name}", "vmpooler__completed__#{pool_name}", vm)
      $logger.log('d', "[!] [#{pool_name}] '#{vm}' has mismatched hostname #{hostname}, removed from 'ready' queue")
      true
    end

    def check_running_vm(vm, pool, ttl, provider)
      Thread.new do
        begin
          _check_running_vm(vm, pool, ttl, provider)
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool}] '#{vm}' failed while checking VM with an error: #{e}")
          raise
        end
      end
    end

    def _check_running_vm(vm, pool, ttl, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        catch :stop_checking do
          @redis.with_metrics do |redis|
            # Check that VM is within defined lifetime
            checkouttime = redis.hget("vmpooler__active__#{pool}", vm)
            if checkouttime
              time_since_checkout = Time.now - Time.parse(checkouttime)
              running = time_since_checkout / 60 / 60

              if (ttl.to_i > 0) && (running.to_i >= ttl.to_i)
                move_vm_queue(pool, vm, 'running', 'completed', redis, "reached end of TTL after #{ttl} hours")
                throw :stop_checking
              end
            else
              move_vm_queue(pool, vm, 'running', 'completed', redis, 'is listed as running, but has no checkouttime data. Removing from running')
            end

            # tag VM if not tagged yet, this ensures the method is only called once
            unless redis.hget("vmpooler__vm__#{vm}", 'user_tagged')
              success = provider.tag_vm_user(pool, vm)
              redis.hset("vmpooler__vm__#{vm}", 'user_tagged', 'true') if success
            end

            throw :stop_checking if provider.vm_ready?(pool, vm, redis)

            throw :stop_checking if provider.get_vm(pool, vm)

            move_vm_queue(pool, vm, 'running', 'completed', redis, 'is no longer in inventory, removing from running')
          end
        end
      end
    end

    def move_vm_queue(pool, vm, queue_from, queue_to, redis, msg = nil)
      redis.smove("vmpooler__#{queue_from}__#{pool}", "vmpooler__#{queue_to}__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' #{msg}") if msg
    end

    # Dead-Letter Queue (DLQ) helper methods
    def dlq_enabled?
      $config[:config] && $config[:config]['dlq_enabled'] == true
    end

    def dlq_ttl
      ($config[:config] && $config[:config]['dlq_ttl']) || 168 # default 7 days in hours
    end

    def dlq_max_entries
      ($config[:config] && $config[:config]['dlq_max_entries']) || 10_000
    end

    def move_to_dlq(vm, pool, queue_type, error_class, error_message, redis, request_id: nil, pool_alias: nil, retry_count: 0, skip_metrics: false)
      return unless dlq_enabled?

      dlq_key = "vmpooler__dlq__#{queue_type}"
      timestamp = Time.now.to_i

      # Build DLQ entry
      dlq_entry = {
        'vm' => vm,
        'pool' => pool,
        'queue_from' => queue_type,
        'error_class' => error_class.to_s,
        'error_message' => error_message.to_s,
        'failed_at' => Time.now.iso8601,
        'retry_count' => retry_count,
        'request_id' => request_id,
        'pool_alias' => pool_alias
      }.compact

      # Use sorted set with timestamp as score for easy age-based queries and TTL
      dlq_entry_json = dlq_entry.to_json
      redis.zadd(dlq_key, timestamp, "#{vm}:#{timestamp}:#{dlq_entry_json}")

      # Enforce max entries limit by removing oldest entries
      current_size = redis.zcard(dlq_key)
      if current_size > dlq_max_entries
        remove_count = current_size - dlq_max_entries
        redis.zremrangebyrank(dlq_key, 0, remove_count - 1)
        $logger.log('d', "[!] [dlq] Trimmed #{remove_count} oldest entries from #{dlq_key}")
      end

      # Set expiration on the entire DLQ (will be refreshed on next write)
      ttl_seconds = dlq_ttl * 3600
      redis.expire(dlq_key, ttl_seconds)

      $metrics.increment("dlq.#{queue_type}.count") unless skip_metrics
      $logger.log('d', "[!] [dlq] Moved '#{vm}' from '#{queue_type}' queue to DLQ: #{error_message}")
    rescue StandardError => e
      $logger.log('s', "[!] [dlq] Failed to move '#{vm}' to DLQ: #{e}")
    end

    # Clone a VM
    def clone_vm(pool_name, provider, dns_plugin, request_id = nil, pool_alias = nil)
      Thread.new do
        begin
          _clone_vm(pool_name, provider, dns_plugin, request_id, pool_alias)
        rescue StandardError => e
          if request_id
            $logger.log('s', "[!] [#{pool_name}] failed while cloning VM for request #{request_id} with an error: #{e}")
            @redis.with_metrics do |redis|
              # Only re-queue if the request wasn't already marked as failed (e.g., by permanent error detection)
              request_status = redis.hget("vmpooler__odrequest__#{request_id}", 'status')
              if request_status != 'failed'
                redis.zadd('vmpooler__odcreate__task', 1, "#{pool_alias}:#{pool_name}:1:#{request_id}")
              else
                $logger.log('s', "[!] [#{pool_name}] Request #{request_id} already marked as failed, not re-queueing")
              end
            end
          else
            $logger.log('s', "[!] [#{pool_name}] failed while cloning VM with an error: #{e}")
          end
          raise
        end
      end
    end

    def generate_and_check_hostname
      # Generate a randomized hostname. The total name must no longer than 15
      # character including the hyphen. The shortest adjective in the corpus is
      # three characters long. Therefore, we can technically select a noun up to 11
      # characters long and still be guaranteed to have an available adjective.
      # Because of the limited set of 11 letter nouns and corresponding 3
      # letter adjectives, we actually limit the noun to 10 letters to avoid
      # inviting more conflicts. We favor selecting a longer noun rather than a
      # longer adjective because longer adjectives tend to be less fun.
      @redis.with do |redis|
        noun = @name_generator.noun(max: 10)
        adjective = @name_generator.adjective(max: 14 - noun.length)
        random_name = [adjective, noun].join('-')
        hostname = $config[:config]['prefix'] + random_name
        available = redis.hlen("vmpooler__vm__#{hostname}") == 0

        [hostname, available]
      end
    end

    def find_unique_hostname(pool_name)
      # generate hostname that is not already in use in vmpooler
      # also check that no dns record already exists
      hostname_retries = 0
      max_hostname_retries = 3
      while hostname_retries < max_hostname_retries
        hostname, hostname_available = generate_and_check_hostname
        domain = Vmpooler::Dns.get_domain_for_pool(config, pool_name)
        fqdn = "#{hostname}.#{domain}"

        # skip dns check if the provider is set to skip_dns_check_before_creating_vm
        provider = get_provider_for_pool(pool_name)
        if provider && provider.provider_config['skip_dns_check_before_creating_vm']
          dns_available = true
        else
          dns_ip, dns_available = check_dns_available(fqdn)
        end

        break if hostname_available && dns_available

        hostname_retries += 1

        if !hostname_available
          $metrics.increment("errors.duplicatehostname.#{pool_name}")
          $logger.log('s', "[!] [#{pool_name}] Generated hostname #{fqdn} was not unique (attempt \##{hostname_retries} of #{max_hostname_retries})")
        elsif !dns_available
          $metrics.increment("errors.staledns.#{pool_name}")
          $logger.log('s', "[!] [#{pool_name}] Generated hostname #{fqdn} already exists in DNS records (#{dns_ip}), stale DNS")
        end
      end

      raise "Unable to generate a unique hostname after #{hostname_retries} attempts. The last hostname checked was #{fqdn}" unless hostname_available && dns_available

      hostname
    end

    # Query the DNS for the name we want to create and if it already exists, mark it unavailable
    # This protects against stale DNS records
    def check_dns_available(vm_name)
      begin
        dns_ip = Resolv.getaddress(vm_name)
      rescue Resolv::ResolvError
        # this is the expected case, swallow the error
        # eg "no address for blah-daisy.example.com"
        return ['', true]
      end
      [dns_ip, false]
    end

    def _clone_vm(pool_name, provider, dns_plugin, request_id = nil, pool_alias = nil)
      new_vmname = find_unique_hostname(pool_name)
      pool_domain = Vmpooler::Dns.get_domain_for_pool(config, pool_name)
      mutex = vm_mutex(new_vmname)
      mutex.synchronize do
        @redis.with_metrics do |redis|
          redis.multi do |transaction|
            transaction.sadd("vmpooler__pending__#{pool_name}", new_vmname)
            transaction.hset("vmpooler__vm__#{new_vmname}", 'clone', Time.now.to_s)
            transaction.hset("vmpooler__vm__#{new_vmname}", 'template', pool_name) # This value is used to represent the pool.
            transaction.hset("vmpooler__vm__#{new_vmname}", 'pool', pool_name)
            transaction.hset("vmpooler__vm__#{new_vmname}", 'domain', pool_domain)
            transaction.hset("vmpooler__vm__#{new_vmname}", 'request_id', request_id) if request_id
            transaction.hset("vmpooler__vm__#{new_vmname}", 'pool_alias', pool_alias) if pool_alias
          end
        end

        begin
          $logger.log('d', "[ ] [#{pool_name}] Starting to clone '#{new_vmname}'")
          start = Time.now
          provider.create_vm(pool_name, new_vmname)
          finish = format('%<time>.2f', time: Time.now - start)
          $logger.log('s', "[+] [#{pool_name}] '#{new_vmname}' cloned in #{finish} seconds")
          $metrics.timing("clone.#{pool_name}", finish)

          $logger.log('d', "[ ] [#{pool_name}] Obtaining IP for '#{new_vmname}'")
          ip_start = Time.now
          ip = provider.get_vm_ip_address(new_vmname, pool_name)
          ip_finish = format('%<time>.2f', time: Time.now - ip_start)

          raise StandardError, "failed to obtain IP after #{ip_finish} seconds" if ip.nil?

          $logger.log('s', "[+] [#{pool_name}] Obtained IP for '#{new_vmname}' in #{ip_finish} seconds")

          @redis.with_metrics do |redis|
            redis.pipelined do |pipeline|
              pipeline.hset("vmpooler__clone__#{Date.today}", "#{pool_name}:#{new_vmname}", finish)
              pipeline.hset("vmpooler__vm__#{new_vmname}", 'clone_time', finish)
              pipeline.hset("vmpooler__vm__#{new_vmname}", 'ip', ip)
            end
          end

          dns_plugin_class_name = get_dns_plugin_class_name_for_pool(pool_name)
          dns_plugin.create_or_replace_record(new_vmname) unless dns_plugin_class_name == 'dynamic-dns'
        rescue StandardError => e
          # Store error details for retry decision making
          @redis.with_metrics do |redis|
            # Get retry count before moving to DLQ
            retry_count = 0
            if request_id
              ondemandrequest_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
              retry_count = ondemandrequest_hash['retry_count'].to_i if ondemandrequest_hash
            end

            # Move to DLQ before removing from pending queue
            move_to_dlq(new_vmname, pool_name, 'clone', e.class.name, e.message,
                        redis, request_id: request_id, pool_alias: pool_alias, retry_count: retry_count)

            redis.pipelined do |pipeline|
              pipeline.srem("vmpooler__pending__#{pool_name}", new_vmname)
              pipeline.hset("vmpooler__vm__#{new_vmname}", 'clone_error', e.message)
              pipeline.hset("vmpooler__vm__#{new_vmname}", 'clone_error_class', e.class.name)
              expiration_ttl = $config[:redis]['data_ttl'].to_i * 60 * 60
              pipeline.expire("vmpooler__vm__#{new_vmname}", expiration_ttl)
            end

            # Handle retry logic for on-demand requests
            if request_id
              retry_count = (redis.hget("vmpooler__odrequest__#{request_id}", 'retry_count') || '0').to_i
              max_retries = $config[:config]['max_vm_retries'] || 3
              is_permanent = permanent_error?(e.message, e.class.name)

              $logger.log('s', "[!] [#{pool_name}] '#{new_vmname}' checking immediate failure retry: error='#{e.message}', error_class='#{e.class.name}', retry_count=#{retry_count}, max_retries=#{max_retries}, permanent_error=#{is_permanent}")

              if is_permanent || retry_count >= max_retries
                reason = is_permanent ? 'permanent error detected' : 'max retries exceeded'
                $logger.log('s', "[!] [#{pool_name}] Cancelling request #{request_id} due to #{reason}")
                redis.hset("vmpooler__odrequest__#{request_id}", 'status', 'failed')
                redis.zadd('vmpooler__odcreate__task', 0, "#{pool_alias}:#{pool_name}:0:#{request_id}")
              else
                # Increment retry count and re-queue for retry
                redis.hincrby("vmpooler__odrequest__#{request_id}", 'retry_count', 1)
                $logger.log('s', "[+] [#{pool_name}] Request #{request_id} will be retried (attempt #{retry_count + 1}/#{max_retries})")
                redis.zadd('vmpooler__odcreate__task', 1, "#{pool_alias}:#{pool_name}:1:#{request_id}")
              end
            end
          end
          $logger.log('s', "[!] [#{pool_name}] '#{new_vmname}' clone failed: #{e.class}: #{e.message}")
          raise
        ensure
          @redis.with_metrics do |redis|
            redis.decr('vmpooler__tasks__ondemandclone') if request_id
            redis.decr('vmpooler__tasks__clone') unless request_id
          end
        end
      end
    end

    # Destroy a VM
    def destroy_vm(vm, pool, provider, dns_plugin)
      Thread.new do
        begin
          _destroy_vm(vm, pool, provider, dns_plugin)
        rescue StandardError => e
          $logger.log('d', "[!] [#{pool}] '#{vm}' failed while destroying the VM with an error: #{e}")
          raise
        end
      end
    end

    def _destroy_vm(vm, pool, provider, dns_plugin)
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        @redis.with_metrics do |redis|
          redis.pipelined do |pipeline|
            pipeline.hdel("vmpooler__active__#{pool}", vm)
            pipeline.hset("vmpooler__vm__#{vm}", 'destroy', Time.now.to_s)

            # Auto-expire metadata key
            pipeline.expire("vmpooler__vm__#{vm}", ($config[:redis]['data_ttl'].to_i * 60 * 60))
          end

          start = Time.now

          provider.destroy_vm(pool, vm)
          domain = get_dns_plugin_domain_for_pool(pool)
          fqdn = "#{vm}.#{domain}"

          dns_plugin_class_name = get_dns_plugin_class_name_for_pool(pool)
          dns_plugin.delete_record(fqdn) unless dns_plugin_class_name == 'dynamic-dns'

          redis.srem("vmpooler__completed__#{pool}", vm)

          finish = format('%<time>.2f', time: Time.now - start)
          $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
          $metrics.timing("destroy.#{pool}", finish)
        end
      end
      dereference_mutex(vm)
    end

    def purge_unused_vms_and_resources
      global_purge = $config[:config]['purge_unconfigured_resources']
      providers = $config[:providers].keys
      providers.each do |provider_key|
        provider_purge = $config[:providers][provider_key]['purge_unconfigured_resources'] || global_purge
        if provider_purge
          Thread.new do
            begin
              purge_vms_and_resources(provider_key)
            rescue StandardError => e
              $logger.log('s', "[!] failed while purging provider #{provider_key} VMs and folders with an error: #{e}")
            end
          end
        end
      end
      nil
    end

    def purge_vms_and_resources(provider_name)
      provider = $providers[provider_name.to_s]
      # Deprecated, will be removed in version 3
      if provider.provider_config['folder_whitelist']
        $logger.log('d', "[!] [deprecation] rename configuration 'folder_whitelist' to 'resources_allowlist' for provider #{provider_name}")
        allowlist = provider.provider_config['folder_whitelist']
      else
        allowlist = provider.provider_config['resources_allowlist']
      end
      provider.purge_unconfigured_resources(allowlist)
    end

    # Auto-purge stale queue entries
    def purge_enabled?
      $config[:config] && $config[:config]['purge_enabled'] == true
    end

    def purge_dry_run?
      $config[:config] && $config[:config]['purge_dry_run'] == true
    end

    def max_pending_age
      ($config[:config] && $config[:config]['max_pending_age']) || 7200 # default 2 hours in seconds
    end

    def max_ready_age
      ($config[:config] && $config[:config]['max_ready_age']) || 86_400 # default 24 hours in seconds
    end

    def max_completed_age
      ($config[:config] && $config[:config]['max_completed_age']) || 3600 # default 1 hour in seconds
    end

    def max_orphaned_age
      ($config[:config] && $config[:config]['max_orphaned_age']) || 86_400 # default 24 hours in seconds
    end

    def purge_stale_queue_entries
      return unless purge_enabled?

      Thread.new do
        begin
          $logger.log('d', '[*] [purge] Starting stale queue entry purge cycle')
          purge_start = Time.now

          @redis.with_metrics do |redis|
            total_purged = 0

            # Purge stale entries from each pool
            $config[:pools].each do |pool|
              pool_name = pool['name']

              # Purge pending queue
              purged_pending = purge_pending_queue(pool_name, redis)
              total_purged += purged_pending

              # Purge ready queue
              purged_ready = purge_ready_queue(pool_name, redis)
              total_purged += purged_ready

              # Purge completed queue
              purged_completed = purge_completed_queue(pool_name, redis)
              total_purged += purged_completed
            end

            # Purge orphaned VM metadata
            purged_orphaned = purge_orphaned_metadata(redis)
            total_purged += purged_orphaned

            purge_duration = Time.now - purge_start
            $logger.log('s', "[*] [purge] Completed purge cycle in #{purge_duration.round(2)}s: #{total_purged} entries purged")
            $metrics.timing('purge.cycle.duration', purge_duration)
            $metrics.gauge('purge.total.count', total_purged)
          end
        rescue StandardError => e
          $logger.log('s', "[!] [purge] Failed during purge cycle: #{e}")
        end
      end
    end

    def purge_pending_queue(pool_name, redis)
      queue_key = "vmpooler__pending__#{pool_name}"
      vms = redis.smembers(queue_key)
      purged_count = 0

      vms.each do |vm|
        begin
          clone_time_str = redis.hget("vmpooler__vm__#{vm}", 'clone')
          next unless clone_time_str

          clone_time = Time.parse(clone_time_str)
          age = Time.now - clone_time

          if age > max_pending_age
            request_id = redis.hget("vmpooler__vm__#{vm}", 'request_id')
            pool_alias = redis.hget("vmpooler__vm__#{vm}", 'pool_alias')

            purged_count += 1

            if purge_dry_run?
              $logger.log('d', "[*] [purge][dry-run] Would purge stale pending VM '#{vm}' (age: #{age.round(0)}s, max: #{max_pending_age}s)")
            else
              # Move to DLQ before removing (skip DLQ metric since we're tracking purge metric)
              move_to_dlq(vm, pool_name, 'pending', 'Purge',
                          "Stale pending VM (age: #{age.round(0)}s > max: #{max_pending_age}s)",
                          redis, request_id: request_id, pool_alias: pool_alias, skip_metrics: true)

              redis.srem(queue_key, vm)

              # Set expiration on VM metadata if data_ttl is configured
              if $config[:redis] && $config[:redis]['data_ttl']
                expiration_ttl = $config[:redis]['data_ttl'].to_i * 60 * 60
                redis.expire("vmpooler__vm__#{vm}", expiration_ttl)
              end

              $logger.log('d', "[!] [purge] Purged stale pending VM '#{vm}' from '#{pool_name}' (age: #{age.round(0)}s)")
              $metrics.increment("purge.pending.#{pool_name}.count")
            end
          end
        rescue StandardError => e
          $logger.log('d', "[!] [purge] Error checking pending VM '#{vm}': #{e}")
        end
      end

      purged_count
    end

    def purge_ready_queue(pool_name, redis)
      queue_key = "vmpooler__ready__#{pool_name}"
      vms = redis.smembers(queue_key)
      purged_count = 0

      vms.each do |vm|
        begin
          ready_time_str = redis.hget("vmpooler__vm__#{vm}", 'ready')
          next unless ready_time_str

          ready_time = Time.parse(ready_time_str)
          age = Time.now - ready_time

          if age > max_ready_age
            if purge_dry_run?
              $logger.log('d', "[*] [purge][dry-run] Would purge stale ready VM '#{vm}' (age: #{age.round(0)}s, max: #{max_ready_age}s)")
            else
              redis.smove(queue_key, "vmpooler__completed__#{pool_name}", vm)
              $logger.log('d', "[!] [purge] Moved stale ready VM '#{vm}' from '#{pool_name}' to completed (age: #{age.round(0)}s)")
              $metrics.increment("purge.ready.#{pool_name}.count")
            end
            purged_count += 1
          end
        rescue StandardError => e
          $logger.log('d', "[!] [purge] Error checking ready VM '#{vm}': #{e}")
        end
      end

      purged_count
    end

    def purge_completed_queue(pool_name, redis)
      queue_key = "vmpooler__completed__#{pool_name}"
      vms = redis.smembers(queue_key)
      purged_count = 0

      vms.each do |vm|
        begin
          # Check destroy time or last activity time
          destroy_time_str = redis.hget("vmpooler__vm__#{vm}", 'destroy')
          checkout_time_str = redis.hget("vmpooler__vm__#{vm}", 'checkout')

          # Use the most recent timestamp
          timestamp_str = destroy_time_str || checkout_time_str
          next unless timestamp_str

          timestamp = Time.parse(timestamp_str)
          age = Time.now - timestamp

          if age > max_completed_age
            if purge_dry_run?
              $logger.log('d', "[*] [purge][dry-run] Would purge stale completed VM '#{vm}' (age: #{age.round(0)}s, max: #{max_completed_age}s)")
            else
              redis.srem(queue_key, vm)
              $logger.log('d', "[!] [purge] Removed stale completed VM '#{vm}' from '#{pool_name}' (age: #{age.round(0)}s)")
              $metrics.increment("purge.completed.#{pool_name}.count")
            end
            purged_count += 1
          end
        rescue StandardError => e
          $logger.log('d', "[!] [purge] Error checking completed VM '#{vm}': #{e}")
        end
      end

      purged_count
    end

    def purge_orphaned_metadata(redis)
      # Find VM metadata that doesn't belong to any queue
      all_vm_keys = redis.keys('vmpooler__vm__*')
      purged_count = 0

      all_vm_keys.each do |vm_key|
        begin
          vm = vm_key.sub('vmpooler__vm__', '')

          # Check if VM exists in any queue
          pool_name = redis.hget(vm_key, 'pool')
          next unless pool_name

          in_pending = redis.sismember("vmpooler__pending__#{pool_name}", vm)
          in_ready = redis.sismember("vmpooler__ready__#{pool_name}", vm)
          in_running = redis.sismember("vmpooler__running__#{pool_name}", vm)
          in_completed = redis.sismember("vmpooler__completed__#{pool_name}", vm)
          in_discovered = redis.sismember("vmpooler__discovered__#{pool_name}", vm)
          in_migrating = redis.sismember("vmpooler__migrating__#{pool_name}", vm)

          # VM is orphaned if not in any queue
          unless in_pending || in_ready || in_running || in_completed || in_discovered || in_migrating
            # Check age
            clone_time_str = redis.hget(vm_key, 'clone')
            next unless clone_time_str

            clone_time = Time.parse(clone_time_str)
            age = Time.now - clone_time

            if age > max_orphaned_age
              if purge_dry_run?
                $logger.log('d', "[*] [purge][dry-run] Would purge orphaned metadata for '#{vm}' (age: #{age.round(0)}s, max: #{max_orphaned_age}s)")
              else
                expiration_ttl = 3600 # 1 hour
                redis.expire(vm_key, expiration_ttl)
                $logger.log('d', "[!] [purge] Set expiration on orphaned metadata for '#{vm}' (age: #{age.round(0)}s)")
                $metrics.increment('purge.orphaned.count')
              end
              purged_count += 1
            end
          end
        rescue StandardError => e
          $logger.log('d', "[!] [purge] Error checking orphaned metadata '#{vm_key}': #{e}")
        end
      end

      purged_count
    end

    # Health checks for Redis queues
    def health_check_enabled?
      $config[:config] && $config[:config]['health_check_enabled'] == true
    end

    def health_thresholds
      defaults = {
        'pending_queue_max' => 100,
        'ready_queue_max' => 500,
        'dlq_max_warning' => 100,
        'dlq_max_critical' => 1000,
        'stuck_vm_age_threshold' => 7200, # 2 hours
        'stuck_vm_max_warning' => 10,
        'stuck_vm_max_critical' => 50
      }

      if $config[:config] && $config[:config]['health_thresholds']
        defaults.merge($config[:config]['health_thresholds'])
      else
        defaults
      end
    end

    def check_queue_health
      return unless health_check_enabled?

      Thread.new do
        begin
          $logger.log('d', '[*] [health] Running queue health check')
          health_start = Time.now

          @redis.with_metrics do |redis|
            health_metrics = calculate_health_metrics(redis)
            health_status = determine_health_status(health_metrics)

            # Store health metrics in Redis for API consumption
            redis.hmset('vmpooler__health', *health_metrics.to_a.flatten)
            redis.hset('vmpooler__health', 'status', health_status)
            redis.hset('vmpooler__health', 'last_check', Time.now.iso8601)
            redis.expire('vmpooler__health', 3600) # Expire after 1 hour

            # Log health summary
            log_health_summary(health_metrics, health_status)

            # Push metrics
            push_health_metrics(health_metrics, health_status)

            health_duration = Time.now - health_start
            $metrics.timing('health.check.duration', health_duration)
          end
        rescue StandardError => e
          $logger.log('s', "[!] [health] Failed during health check: #{e}")
        end
      end
    end

    def calculate_health_metrics(redis)
      metrics = {
        'queues' => {},
        'tasks' => {},
        'errors' => {}
      }

      total_stuck_vms = 0
      total_dlq_size = 0
      thresholds = health_thresholds

      # Check each pool's queues
      $config[:pools].each do |pool|
        pool_name = pool['name']
        metrics['queues'][pool_name] = {}

        # Pending queue metrics
        pending_key = "vmpooler__pending__#{pool_name}"
        pending_vms = redis.smembers(pending_key)
        pending_ages = calculate_queue_ages(pending_vms, 'clone', redis)
        stuck_pending = pending_ages.count { |age| age > thresholds['stuck_vm_age_threshold'] }
        total_stuck_vms += stuck_pending

        metrics['queues'][pool_name]['pending'] = {
          'size' => pending_vms.size,
          'oldest_age' => pending_ages.max || 0,
          'avg_age' => pending_ages.empty? ? 0 : (pending_ages.sum / pending_ages.size).round(0),
          'stuck_count' => stuck_pending
        }

        # Ready queue metrics
        ready_key = "vmpooler__ready__#{pool_name}"
        ready_vms = redis.smembers(ready_key)
        ready_ages = calculate_queue_ages(ready_vms, 'ready', redis)

        metrics['queues'][pool_name]['ready'] = {
          'size' => ready_vms.size,
          'oldest_age' => ready_ages.max || 0,
          'avg_age' => ready_ages.empty? ? 0 : (ready_ages.sum / ready_ages.size).round(0)
        }

        # Completed queue metrics
        completed_key = "vmpooler__completed__#{pool_name}"
        completed_size = redis.scard(completed_key)
        metrics['queues'][pool_name]['completed'] = { 'size' => completed_size }
      end

      # Task queue metrics
      clone_active = redis.get('vmpooler__tasks__clone').to_i
      ondemand_active = redis.get('vmpooler__tasks__ondemandclone').to_i
      odcreate_pending = redis.zcard('vmpooler__odcreate__task')

      metrics['tasks']['clone'] = { 'active' => clone_active }
      metrics['tasks']['ondemand'] = { 'active' => ondemand_active, 'pending' => odcreate_pending }

      # DLQ metrics
      if dlq_enabled?
        dlq_keys = redis.keys('vmpooler__dlq__*')
        dlq_keys.each do |dlq_key|
          queue_type = dlq_key.sub('vmpooler__dlq__', '')
          dlq_size = redis.zcard(dlq_key)
          total_dlq_size += dlq_size
          metrics['queues']['dlq'] ||= {}
          metrics['queues']['dlq'][queue_type] = { 'size' => dlq_size }
        end
      end

      # Error metrics
      metrics['errors']['dlq_total_size'] = total_dlq_size
      metrics['errors']['stuck_vm_count'] = total_stuck_vms

      # Orphaned metadata count
      orphaned_count = count_orphaned_metadata(redis)
      metrics['errors']['orphaned_metadata_count'] = orphaned_count

      metrics
    end

    def calculate_queue_ages(vms, timestamp_field, redis)
      ages = []
      vms.each do |vm|
        begin
          timestamp_str = redis.hget("vmpooler__vm__#{vm}", timestamp_field)
          next unless timestamp_str

          timestamp = Time.parse(timestamp_str)
          age = (Time.now - timestamp).to_i
          ages << age
        rescue StandardError
          # Skip VMs with invalid timestamps
        end
      end
      ages
    end

    def count_orphaned_metadata(redis)
      all_vm_keys = redis.keys('vmpooler__vm__*')
      orphaned_count = 0

      all_vm_keys.each do |vm_key|
        begin
          vm = vm_key.sub('vmpooler__vm__', '')
          pool_name = redis.hget(vm_key, 'pool')
          next unless pool_name

          in_any_queue = redis.sismember("vmpooler__pending__#{pool_name}", vm) ||
                         redis.sismember("vmpooler__ready__#{pool_name}", vm) ||
                         redis.sismember("vmpooler__running__#{pool_name}", vm) ||
                         redis.sismember("vmpooler__completed__#{pool_name}", vm) ||
                         redis.sismember("vmpooler__discovered__#{pool_name}", vm) ||
                         redis.sismember("vmpooler__migrating__#{pool_name}", vm)

          orphaned_count += 1 unless in_any_queue
        rescue StandardError
          # Skip on error
        end
      end

      orphaned_count
    end

    def determine_health_status(metrics)
      thresholds = health_thresholds

      # Check DLQ size
      dlq_size = metrics['errors']['dlq_total_size']
      return 'unhealthy' if dlq_size > thresholds['dlq_max_critical']

      # Check stuck VM count
      stuck_count = metrics['errors']['stuck_vm_count']
      return 'unhealthy' if stuck_count > thresholds['stuck_vm_max_critical']

      # Check queue sizes
      metrics['queues'].each do |pool_name, queues|
        next if pool_name == 'dlq'

        pending_size = begin
          queues['pending']['size']
        rescue StandardError
          0
        end
        ready_size = begin
          queues['ready']['size']
        rescue StandardError
          0
        end

        return 'unhealthy' if pending_size > thresholds['pending_queue_max'] * 2
        return 'unhealthy' if ready_size > thresholds['ready_queue_max'] * 2
      end

      # Check for degraded conditions
      return 'degraded' if dlq_size > thresholds['dlq_max_warning']
      return 'degraded' if stuck_count > thresholds['stuck_vm_max_warning']

      metrics['queues'].each do |pool_name, queues|
        next if pool_name == 'dlq'

        pending_size = begin
          queues['pending']['size']
        rescue StandardError
          0
        end
        ready_size = begin
          queues['ready']['size']
        rescue StandardError
          0
        end

        return 'degraded' if pending_size > thresholds['pending_queue_max']
        return 'degraded' if ready_size > thresholds['ready_queue_max']
      end

      'healthy'
    end

    def log_health_summary(metrics, status)
      summary = "[*] [health] Status: #{status.upcase}"

      # Queue summary
      total_pending = 0
      total_ready = 0
      total_completed = 0

      metrics['queues'].each do |pool_name, queues|
        next if pool_name == 'dlq'

        total_pending += begin
          queues['pending']['size']
        rescue StandardError
          0
        end
        total_ready += begin
          queues['ready']['size']
        rescue StandardError
          0
        end
        total_completed += begin
          queues['completed']['size']
        rescue StandardError
          0
        end
      end

      summary += " | Queues: P=#{total_pending} R=#{total_ready} C=#{total_completed}"
      summary += " | DLQ=#{metrics['errors']['dlq_total_size']}"
      summary += " | Stuck=#{metrics['errors']['stuck_vm_count']}"
      summary += " | Orphaned=#{metrics['errors']['orphaned_metadata_count']}"

      log_level = status == 'healthy' ? 's' : 'd'
      $logger.log(log_level, summary)
    end

    def push_health_metrics(metrics, status)
      # Push error metrics first
      $metrics.gauge('health.dlq.total_size', metrics['errors']['dlq_total_size'])
      $metrics.gauge('health.stuck_vms.count', metrics['errors']['stuck_vm_count'])
      $metrics.gauge('health.orphaned_metadata.count', metrics['errors']['orphaned_metadata_count'])

      # Push per-pool queue metrics
      metrics['queues'].each do |pool_name, queues|
        next if pool_name == 'dlq'

        $metrics.gauge("health.queue.#{pool_name}.pending.size", queues['pending']['size'])
        $metrics.gauge("health.queue.#{pool_name}.pending.oldest_age", queues['pending']['oldest_age'])
        $metrics.gauge("health.queue.#{pool_name}.pending.stuck_count", queues['pending']['stuck_count'])

        $metrics.gauge("health.queue.#{pool_name}.ready.size", queues['ready']['size'])
        $metrics.gauge("health.queue.#{pool_name}.ready.oldest_age", queues['ready']['oldest_age'])

        $metrics.gauge("health.queue.#{pool_name}.completed.size", queues['completed']['size'])
      end

      # Push DLQ metrics
      metrics['queues']['dlq']&.each do |queue_type, dlq_metrics|
        $metrics.gauge("health.dlq.#{queue_type}.size", dlq_metrics['size'])
      end

      # Push task metrics
      $metrics.gauge('health.tasks.clone.active', metrics['tasks']['clone']['active'])
      $metrics.gauge('health.tasks.ondemand.active', metrics['tasks']['ondemand']['active'])
      $metrics.gauge('health.tasks.ondemand.pending', metrics['tasks']['ondemand']['pending'])

      # Push status last (0=healthy, 1=degraded, 2=unhealthy)
      status_value = { 'healthy' => 0, 'degraded' => 1, 'unhealthy' => 2 }[status] || 2
      $metrics.gauge('health.status', status_value)
    end

    def create_vm_disk(pool_name, vm, disk_size, provider)
      Thread.new do
        begin
          _create_vm_disk(pool_name, vm, disk_size, provider)
        rescue StandardError => e
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while creating disk: #{e}")
          raise
        end
      end
    end

    def _create_vm_disk(pool_name, vm_name, disk_size, provider)
      raise("Invalid disk size of '#{disk_size}' passed") if disk_size.nil? || disk_size.empty? || disk_size.to_i <= 0

      $logger.log('s', "[ ] [disk_manager] '#{vm_name}' is attaching a #{disk_size}gb disk")

      start = Time.now

      result = provider.create_disk(pool_name, vm_name, disk_size.to_i)

      finish = format('%<time>.2f', time: Time.now - start)

      if result
        @redis.with_metrics do |redis|
          rdisks = redis.hget("vmpooler__vm__#{vm_name}", 'disk')
          disks = rdisks ? rdisks.split(':') : []
          disks.push("+#{disk_size}gb")
          redis.hset("vmpooler__vm__#{vm_name}", 'disk', disks.join(':'))
        end

        $logger.log('s', "[+] [disk_manager] '#{vm_name}' attached #{disk_size}gb disk in #{finish} seconds")
      else
        $logger.log('s', "[+] [disk_manager] '#{vm_name}' failed to attach disk")
      end

      result
    end

    def create_vm_snapshot(pool_name, vm, snapshot_name, provider)
      Thread.new do
        begin
          _create_vm_snapshot(pool_name, vm, snapshot_name, provider)
        rescue StandardError => e
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while creating snapshot: #{e}")
          raise
        end
      end
    end

    def _create_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
      $logger.log('s', "[ ] [snapshot_manager] 'Attempting to snapshot #{vm_name} in pool #{pool_name}")
      start = Time.now

      result = provider.create_snapshot(pool_name, vm_name, snapshot_name)

      finish = format('%<time>.2f', time: Time.now - start)

      if result
        @redis.with_metrics do |redis|
          redis.hset("vmpooler__vm__#{vm_name}", "snapshot:#{snapshot_name}", Time.now.to_s)
        end
        $logger.log('s', "[+] [snapshot_manager] '#{vm_name}' snapshot created in #{finish} seconds")
      else
        $logger.log('s', "[+] [snapshot_manager] Failed to snapshot '#{vm_name}'")
      end

      result
    end

    def revert_vm_snapshot(pool_name, vm, snapshot_name, provider)
      Thread.new do
        begin
          _revert_vm_snapshot(pool_name, vm, snapshot_name, provider)
        rescue StandardError => e
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while reverting snapshot: #{e}")
          raise
        end
      end
    end

    def _revert_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
      $logger.log('s', "[ ] [snapshot_manager] 'Attempting to revert #{vm_name}' in pool #{pool_name} to snapshot '#{snapshot_name}'")
      start = Time.now

      result = provider.revert_snapshot(pool_name, vm_name, snapshot_name)

      finish = format('%<time>.2f', time: Time.now - start)

      if result
        $logger.log('s', "[+] [snapshot_manager] '#{vm_name}' reverted to snapshot '#{snapshot_name}' in #{finish} seconds")
      else
        $logger.log('s', "[+] [snapshot_manager] Failed to revert #{vm_name}' in pool #{pool_name} to snapshot '#{snapshot_name}'")
      end

      result
    end

    # load only dns plugins used in config file
    def load_used_dns_plugins
      dns_plugins = Vmpooler::Dns.get_dns_plugin_config_classes(config)
      Vmpooler::Dns.load_by_name(dns_plugins)
    end

    # load only providers used in config file
    def load_used_providers
      Vmpooler::Providers.load_by_name(used_providers)
    end

    # @return [Array] - a list of used providers from the config file, defaults to the default providers
    # ie. ["dummy"]
    def used_providers
      # create an array of provider classes based on the config
      if config[:providers]
        config_provider_names = config[:providers].keys
        config_providers = config_provider_names.map do |config_provider_name|
          if config[:providers][config_provider_name] && config[:providers][config_provider_name]['provider_class']
            config[:providers][config_provider_name]['provider_class'].to_s
          else
            config_provider_name.to_s
          end
        end.compact.uniq
      else
        config_providers = []
      end
      # return the unique array of providers from the config and VMPooler defaults
      @used_providers ||= (config_providers + default_providers).uniq
    end

    # @return [Array] - returns a list of providers that should always be loaded
    # note: vsphere is the default if user does not specify although this should not be
    # if vsphere is to no longer be loaded by default please remove
    def default_providers
      @default_providers ||= %w[dummy]
    end

    def get_pool_name_for_vm(vm_name, redis)
      # the 'template' is a bad name.  Should really be 'poolname'
      redis.hget("vmpooler__vm__#{vm_name}", 'template')
    end

    # @param pool_name [String] - the name of the pool
    # @return [Provider] - returns the provider class Object
    def get_provider_for_pool(pool_name)
      pool = $config[:pools].find { |p| p['name'] == pool_name }
      return nil unless pool

      provider_name = pool.fetch('provider', nil)
      $providers[provider_name]
    end

    def get_dns_plugin_class_name_for_pool(pool_name)
      pool = $config[:pools].find { |p| p['name'] == pool_name }
      return nil unless pool

      plugin_name = pool.fetch('dns_plugin')
      Vmpooler::Dns.get_dns_plugin_class_by_name(config, plugin_name)
    end

    def get_dns_plugin_class_for_pool(pool_name)
      pool = $config[:pools].find { |p| p['name'] == pool_name }
      return nil unless pool

      plugin_name = pool.fetch('dns_plugin')
      plugin_class = Vmpooler::Dns.get_dns_plugin_class_by_name(config, plugin_name)
      $dns_plugins[plugin_class]
    end

    def get_dns_plugin_domain_for_pool(pool_name)
      pool = $config[:pools].find { |p| p['name'] == pool_name }
      return nil unless pool

      plugin_name = pool.fetch('dns_plugin')
      Vmpooler::Dns.get_dns_plugin_domain_by_name(config, plugin_name)
    end

    def check_disk_queue(maxloop = 0, loop_delay = 5)
      $logger.log('d', '[*] [disk_manager] starting worker thread')

      $threads['disk_manager'] = Thread.new do
        loop_count = 1
        loop do
          _check_disk_queue
          sleep(loop_delay)

          unless maxloop == 0
            break if loop_count >= maxloop

            loop_count += 1
          end
        end
      end
    end

    def _check_disk_queue
      @redis.with_metrics do |redis|
        task_detail = redis.spop('vmpooler__tasks__disk')
        unless task_detail.nil?
          begin
            vm_name, disk_size = task_detail.split(':')
            pool_name = get_pool_name_for_vm(vm_name, redis)
            raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

            provider = get_provider_for_pool(pool_name)
            raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

            create_vm_disk(pool_name, vm_name, disk_size, provider)
          rescue StandardError => e
            $logger.log('s', "[!] [disk_manager] disk creation appears to have failed: #{e}")
          end
        end
      end
    end

    def check_snapshot_queue(maxloop = 0, loop_delay = 5)
      $logger.log('d', '[*] [snapshot_manager] starting worker thread')

      $threads['snapshot_manager'] = Thread.new do
        loop_count = 1
        loop do
          _check_snapshot_queue
          sleep(loop_delay)

          unless maxloop == 0
            break if loop_count >= maxloop

            loop_count += 1
          end
        end
      end
    end

    def _check_snapshot_queue
      @redis.with_metrics do |redis|
        task_detail = redis.spop('vmpooler__tasks__snapshot')

        unless task_detail.nil?
          begin
            vm_name, snapshot_name = task_detail.split(':')
            pool_name = get_pool_name_for_vm(vm_name, redis)
            raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

            provider = get_provider_for_pool(pool_name)
            raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

            create_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
          rescue StandardError => e
            $logger.log('s', "[!] [snapshot_manager] snapshot create appears to have failed: #{e}")
          end
        end

        task_detail = redis.spop('vmpooler__tasks__snapshot-revert')

        unless task_detail.nil?
          begin
            vm_name, snapshot_name = task_detail.split(':')
            pool_name = get_pool_name_for_vm(vm_name, redis)
            raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

            provider = get_provider_for_pool(pool_name)
            raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

            revert_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
          rescue StandardError => e
            $logger.log('s', "[!] [snapshot_manager] snapshot revert appears to have failed: #{e}")
          end
        end
      end
    end

    def migrate_vm(vm_name, pool_name, provider)
      Thread.new do
        begin
          mutex = vm_mutex(vm_name)
          mutex.synchronize do
            @redis.with_metrics do |redis|
              redis.srem("vmpooler__migrating__#{pool_name}", vm_name)
            end
            provider.migrate_vm(pool_name, vm_name)
          end
        rescue StandardError => e
          $logger.log('s', "[x] [#{pool_name}] '#{vm_name}' migration failed with an error: #{e}")
        end
      end
    end

    # Helper method mainly used for unit testing
    def time_passed?(_event, time)
      Time.now > time
    end

    # Possible wakeup events
    # :pool_size_change
    #   - Fires when the number of ready VMs changes due to being consumed.
    #   - Additional options
    #       :poolname
    # :pool_template_change
    #   - Fires when a template configuration update is requested
    #   - Additional options
    #       :poolname
    # :pool_reset
    #   - Fires when a pool reset is requested
    #   - Additional options
    #       :poolname
    # :undo_override
    #   - Fires when a pool override removal is requested
    #   - Additional options
    #       :poolname
    #
    def sleep_with_wakeup_events(loop_delay, wakeup_period = 5, options = {})
      exit_by = Time.now + loop_delay
      wakeup_by = Time.now + wakeup_period

      return if time_passed?(:exit_by, exit_by)

      @redis.with_metrics do |redis|
        initial_ready_size = redis.scard("vmpooler__ready__#{options[:poolname]}") if options[:pool_size_change]

        initial_clone_target = redis.hget("vmpooler__pool__#{options[:poolname]}", options[:clone_target].to_s) if options[:clone_target_change]

        initial_template = redis.hget('vmpooler__template__prepared', options[:poolname]) if options[:pool_template_change]

        loop do
          sleep(1)
          break if time_passed?(:exit_by, exit_by)

          # Check for wakeup events
          if time_passed?(:wakeup_by, wakeup_by)
            wakeup_by = Time.now + wakeup_period

            # Wakeup if the number of ready VMs has changed
            if options[:pool_size_change]
              ready_size = redis.scard("vmpooler__ready__#{options[:poolname]}")
              break unless ready_size == initial_ready_size
            end

            if options[:clone_target_change]
              clone_target = redis.hget('vmpooler__config__clone_target}', options[:poolname])
              break if clone_target && clone_target != initial_clone_target
            end

            if options[:pool_template_change]
              configured_template = redis.hget('vmpooler__config__template', options[:poolname])
              break if configured_template && initial_template != configured_template
            end

            if options[:pool_reset]
              pending = redis.sismember('vmpooler__poolreset', options[:poolname])
              break if pending
            end

            if options[:undo_override]
              break if redis.sismember('vmpooler__pool__undo_template_override', options[:poolname])
              break if redis.sismember('vmpooler__pool__undo_size_override', options[:poolname])
            end

            if options[:pending_vm]
              pending_vm_count = redis.scard("vmpooler__pending__#{options[:poolname]}")
              break unless pending_vm_count == 0
            end

            if options[:ondemand_request]
              od_request = redis.zcard('vmpooler__provisioning__request')
              od_processing = redis.zcard('vmpooler__provisioning__processing')
              od_createtask = redis.zcard('vmpooler__odcreate__task')

              break unless od_request == 0
              break unless od_processing == 0
              break unless od_createtask == 0
            end
          end

          break if time_passed?(:exit_by, exit_by)
        end
      end
    end

    def check_pool(pool,
                   maxloop = 0,
                   loop_delay_min = CHECK_LOOP_DELAY_MIN_DEFAULT,
                   loop_delay_max = CHECK_LOOP_DELAY_MAX_DEFAULT,
                   loop_delay_decay = CHECK_LOOP_DELAY_DECAY_DEFAULT)
      $logger.log('d', "[*] [#{pool['name']}] starting worker thread")

      # Use the pool setings if they exist
      loop_delay_min = pool['check_loop_delay_min'] unless pool['check_loop_delay_min'].nil?
      loop_delay_max = pool['check_loop_delay_max'] unless pool['check_loop_delay_max'].nil?
      loop_delay_decay = pool['check_loop_delay_decay'] unless pool['check_loop_delay_decay'].nil?

      loop_delay_decay = 2.0 if loop_delay_decay <= 1.0
      loop_delay_max = loop_delay_min if loop_delay_max.nil? || loop_delay_max < loop_delay_min

      $threads[pool['name']] = Thread.new do
        begin
          loop_count = 1
          loop_delay = loop_delay_min
          provider = get_provider_for_pool(pool['name'])
          raise("Could not find provider '#{pool['provider']}'") if provider.nil?

          sync_pool_template(pool)
          loop do
            result = _check_pool(pool, provider)

            if result[:cloned_vms] > 0 || result[:checked_pending_vms] > 0 || result[:discovered_vms] > 0
              loop_delay = loop_delay_min
            else
              loop_delay = (loop_delay * loop_delay_decay).to_i
              loop_delay = loop_delay_max if loop_delay > loop_delay_max
            end
            sleep_with_wakeup_events(loop_delay, loop_delay_min, pool_size_change: true, poolname: pool['name'], pool_template_change: true, clone_target_change: true, pending_vm: true, pool_reset: true, undo_override: true)

            unless maxloop == 0
              break if loop_count >= maxloop

              loop_count += 1
            end
          end
        rescue Redis::CannotConnectError
          raise
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool['name']}] Error while checking the pool: #{e}")
          raise
        end
      end
    end

    def pool_mutex(poolname)
      @reconfigure_pool[poolname] || @reconfigure_pool[poolname] = Mutex.new
    end

    def vm_mutex(vmname)
      @vm_mutex[vmname] || @vm_mutex[vmname] = Mutex.new
    end

    def dereference_mutex(vmname)
      true if @vm_mutex.delete(vmname)
    end

    def sync_pool_template(pool)
      @redis.with_metrics do |redis|
        pool_template = redis.hget('vmpooler__config__template', pool['name'])
        pool['template'] = pool_template if pool_template && pool['template'] != pool_template
      end
    end

    def prepare_template(pool, provider, redis)
      if $config[:config]['create_template_delta_disks'] && !redis.sismember('vmpooler__template__deltas', pool['template'])
        begin
          provider.create_template_delta_disks(pool)
          redis.sadd('vmpooler__template__deltas', pool['template'])
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool['name']}] failed while preparing a template with an error. As a result vmpooler could not create the template delta disks. Either a template delta disk already exists, or the template delta disk creation failed. The error is: #{e}")
        end
      end
      redis.hset('vmpooler__template__prepared', pool['name'], pool['template'])
    end

    def evaluate_template(pool, provider)
      mutex = pool_mutex(pool['name'])
      return if mutex.locked?

      catch :update_not_needed do
        @redis.with_metrics do |redis|
          prepared_template = redis.hget('vmpooler__template__prepared', pool['name'])
          configured_template = redis.hget('vmpooler__config__template', pool['name'])

          if prepared_template.nil?
            mutex.synchronize do
              prepare_template(pool, provider, redis)
              prepared_template = redis.hget('vmpooler__template__prepared', pool['name'])
            end
          elsif prepared_template != pool['template']
            if configured_template.nil?
              mutex.synchronize do
                prepare_template(pool, provider, redis)
                prepared_template = redis.hget('vmpooler__template__prepared', pool['name'])
              end
            end
          end
          throw :update_not_needed if configured_template.nil?
          throw :update_not_needed if configured_template == prepared_template

          mutex.synchronize do
            update_pool_template(pool, provider, configured_template, prepared_template, redis)
          end
        end
      end
    end

    def drain_pool(poolname, redis)
      # Clear a pool of ready and pending instances
      if redis.scard("vmpooler__ready__#{poolname}") > 0
        $logger.log('s', "[*] [#{poolname}] removing ready instances")
        redis.smembers("vmpooler__ready__#{poolname}").each do |vm|
          move_vm_queue(poolname, vm, 'ready', 'completed', redis)
        end
      end
      if redis.scard("vmpooler__pending__#{poolname}") > 0
        $logger.log('s', "[*] [#{poolname}] removing pending instances")
        redis.smembers("vmpooler__pending__#{poolname}").each do |vm|
          move_vm_queue(poolname, vm, 'pending', 'completed', redis)
        end
      end
    end

    def update_pool_template(pool, provider, configured_template, prepared_template, redis)
      pool['template'] = configured_template
      $logger.log('s', "[*] [#{pool['name']}] template updated from #{prepared_template} to #{configured_template}")
      # Remove all ready and pending VMs so new instances are created from the new template
      drain_pool(pool['name'], redis)
      # Prepare template for deployment
      $logger.log('s', "[*] [#{pool['name']}] preparing pool template for deployment")
      prepare_template(pool, provider, redis)
      $logger.log('s', "[*] [#{pool['name']}] is ready for use")
    end

    def update_clone_target(pool)
      mutex = pool_mutex(pool['name'])
      return if mutex.locked?

      @redis.with_metrics do |redis|
        clone_target = redis.hget('vmpooler__config__clone_target', pool['name'])
        break if clone_target.nil?
        break if clone_target == pool['clone_target']

        $logger.log('s', "[*] [#{pool['name']}] clone updated from #{pool['clone_target']} to #{clone_target}")
        mutex.synchronize do
          pool['clone_target'] = clone_target
          # Remove all ready and pending VMs so new instances are created for the new clone_target
          drain_pool(pool['name'], redis)
        end
        $logger.log('s', "[*] [#{pool['name']}] is ready for use")
      end
    end

    def remove_excess_vms(pool)
      @redis.with_metrics do |redis|
        ready = redis.scard("vmpooler__ready__#{pool['name']}")
        pending = redis.scard("vmpooler__pending__#{pool['name']}")
        total = pending.to_i + ready.to_i
        break if total.nil?
        break if total == 0

        mutex = pool_mutex(pool['name'])
        break if mutex.locked?
        break unless ready.to_i > pool['size']

        mutex.synchronize do
          difference = ready.to_i - pool['size']
          difference.times do
            next_vm = redis.spop("vmpooler__ready__#{pool['name']}")
            move_vm_queue(pool['name'], next_vm, 'ready', 'completed', redis)
          end
          if total > ready
            redis.smembers("vmpooler__pending__#{pool['name']}").each do |vm|
              move_vm_queue(pool['name'], vm, 'pending', 'completed', redis)
            end
          end
        end
      end
    end

    def update_pool_size(pool)
      mutex = pool_mutex(pool['name'])
      return if mutex.locked?

      @redis.with_metrics do |redis|
        pool_size_requested = redis.hget('vmpooler__config__poolsize', pool['name'])
        break if pool_size_requested.nil?

        pool_size_requested = Integer(pool_size_requested)
        pool_size_currently = pool['size']
        break if pool_size_requested == pool_size_currently

        mutex.synchronize do
          pool['size'] = pool_size_requested
        end

        $logger.log('s', "[*] [#{pool['name']}] size updated from #{pool_size_currently} to #{pool_size_requested}")
      end
    end

    def reset_pool(pool)
      poolname = pool['name']
      @redis.with_metrics do |redis|
        break unless redis.sismember('vmpooler__poolreset', poolname)

        redis.srem('vmpooler__poolreset', poolname)
        mutex = pool_mutex(poolname)
        mutex.synchronize do
          drain_pool(poolname, redis)
          $logger.log('s', "[*] [#{poolname}] reset has cleared ready and pending instances")
        end
      end
    end

    def undo_override(pool, provider)
      poolname = pool['name']
      mutex = pool_mutex(poolname)
      return if mutex.locked?

      @redis.with_metrics do |redis|
        break unless redis.sismember('vmpooler__pool__undo_template_override', poolname)

        redis.srem('vmpooler__pool__undo_template_override', poolname)
        template_now = pool['template']
        template_original = $config[:pools_at_startup][$config[:pool_index][poolname]]['template']

        mutex.synchronize do
          update_pool_template(pool, provider, template_original, template_now, redis)
        end
      end

      @redis.with_metrics do |redis|
        break unless redis.sismember('vmpooler__pool__undo_size_override', poolname)

        redis.srem('vmpooler__pool__undo_size_override', poolname)
        pool_size_now = pool['size']
        pool_size_original = $config[:pools_at_startup][$config[:pool_index][poolname]]['size']

        mutex.synchronize do
          pool['size'] = pool_size_original
        end

        $logger.log('s', "[*] [#{poolname}] size updated from #{pool_size_now} to #{pool_size_original}")
      end
    end

    def create_inventory(pool, provider, pool_check_response)
      inventory = {}
      begin
        mutex = pool_mutex(pool['name'])
        mutex.synchronize do
          @redis.with_metrics do |redis|
            provider.vms_in_pool(pool['name']).each do |vm|
              if !redis.sismember("vmpooler__running__#{pool['name']}", vm['name']) &&
                 !redis.sismember("vmpooler__ready__#{pool['name']}", vm['name']) &&
                 !redis.sismember("vmpooler__pending__#{pool['name']}", vm['name']) &&
                 !redis.sismember("vmpooler__completed__#{pool['name']}", vm['name']) &&
                 !redis.sismember("vmpooler__discovered__#{pool['name']}", vm['name']) &&
                 !redis.sismember("vmpooler__migrating__#{pool['name']}", vm['name'])

                pool_check_response[:discovered_vms] += 1
                redis.sadd("vmpooler__discovered__#{pool['name']}", vm['name'])

                $logger.log('s', "[?] [#{pool['name']}] '#{vm['name']}' added to 'discovered' queue")
              end

              inventory[vm['name']] = 1
            end
          end
        end
      rescue StandardError => e
        $logger.log('s', "[!] [#{pool['name']}] _check_pool failed with an error while running create_inventory: #{e}")
        raise(e)
      end
      inventory
    end

    def check_running_pool_vms(pool_name, provider, pool_check_response, inventory)
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__running__#{pool_name}").each do |vm|
          if inventory[vm]
            begin
              vm_lifetime = redis.hget("vmpooler__vm__#{vm}", 'lifetime') || $config[:config]['vm_lifetime'] || 12
              pool_check_response[:checked_running_vms] += 1
              check_running_vm(vm, pool_name, vm_lifetime, provider)
            rescue StandardError => e
              $logger.log('d', "[!] [#{pool_name}] _check_pool with an error while evaluating running VMs: #{e}")
            end
          else
            move_vm_queue(pool_name, vm, 'running', 'completed', redis, 'is a running VM but is missing from inventory.  Marking as completed.')
          end
        end
      end
    end

    def check_ready_pool_vms(pool_name, provider, pool_check_response, inventory, pool_ttl)
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__ready__#{pool_name}").each do |vm|
          if inventory[vm]
            begin
              pool_check_response[:checked_ready_vms] += 1
              check_ready_vm(vm, pool_name, pool_ttl, provider)
            rescue StandardError => e
              $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating ready VMs: #{e}")
            end
          else
            move_vm_queue(pool_name, vm, 'ready', 'completed', redis, 'is a ready VM but is missing from inventory.  Marking as completed.')
          end
        end
      end
    end

    def check_pending_pool_vms(pool_name, provider, pool_check_response, inventory, pool_timeout, pool_timeout_notification)
      pool_timeout ||= $config[:config]['timeout'] || 15
      pool_timeout_notification ||= $config[:config]['timeout_notification'] || 5
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__pending__#{pool_name}").reverse.each do |vm|
          if inventory[vm]
            begin
              pool_check_response[:checked_pending_vms] += 1
              check_pending_vm(vm, pool_name, pool_timeout, pool_timeout_notification, provider)
            rescue StandardError => e
              $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating pending VMs: #{e}")
            end
          else
            fail_pending_vm(vm, pool_name, pool_timeout, pool_timeout_notification, redis, exists: false)
          end
        end
      end
    end

    def check_completed_pool_vms(pool_name, provider, pool_check_response, inventory)
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__completed__#{pool_name}").each do |vm|
          if inventory[vm]
            begin
              pool_check_response[:destroyed_vms] += 1
              dns_plugin = get_dns_plugin_class_for_pool(pool_name)
              destroy_vm(vm, pool_name, provider, dns_plugin)
            rescue StandardError => e
              redis.pipelined do |pipeline|
                pipeline.srem("vmpooler__completed__#{pool_name}", vm)
                pipeline.hdel("vmpooler__active__#{pool_name}", vm)
                pipeline.del("vmpooler__vm__#{vm}")
              end
              $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating completed VMs: #{e}")
            end
          else
            $logger.log('s', "[!] [#{pool_name}] '#{vm}' not found in inventory, removed from 'completed' queue")
            redis.pipelined do |pipeline|
              pipeline.srem("vmpooler__completed__#{pool_name}", vm)
              pipeline.hdel("vmpooler__active__#{pool_name}", vm)
              pipeline.del("vmpooler__vm__#{vm}")
            end
          end
        end
      end
    end

    def check_discovered_pool_vms(pool_name)
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__discovered__#{pool_name}").reverse.each do |vm|
          %w[pending ready running completed].each do |queue|
            if redis.sismember("vmpooler__#{queue}__#{pool_name}", vm)
              $logger.log('d', "[!] [#{pool_name}] '#{vm}' found in '#{queue}', removed from 'discovered' queue")
              redis.srem("vmpooler__discovered__#{pool_name}", vm)
            end
          end

          redis.smove("vmpooler__discovered__#{pool_name}", "vmpooler__completed__#{pool_name}", vm) if redis.sismember("vmpooler__discovered__#{pool_name}", vm)
        end
      end
    rescue StandardError => e
      $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating discovered VMs: #{e}")
    end

    def check_migrating_pool_vms(pool_name, provider, pool_check_response, inventory)
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__migrating__#{pool_name}").reverse.each do |vm|
          if inventory[vm]
            begin
              pool_check_response[:migrated_vms] += 1
              migrate_vm(vm, pool_name, provider)
            rescue StandardError => e
              $logger.log('s', "[x] [#{pool_name}] '#{vm}' failed to migrate: #{e}")
            end
          end
        end
      end
    end

    def repopulate_pool_vms(pool_name, provider, pool_check_response, pool_size)
      return if pool_mutex(pool_name).locked?

      @redis.with_metrics do |redis|
        ready = redis.scard("vmpooler__ready__#{pool_name}")
        pending = redis.scard("vmpooler__pending__#{pool_name}")
        running = redis.scard("vmpooler__running__#{pool_name}")

        total = pending.to_i + ready.to_i

        $metrics.gauge("ready.#{pool_name}", ready)
        $metrics.gauge("running.#{pool_name}", running)

        dns_plugin = get_dns_plugin_class_for_pool(pool_name)

        unless pool_size == 0
          if redis.get("vmpooler__empty__#{pool_name}")
            redis.del("vmpooler__empty__#{pool_name}") unless ready == 0
          elsif ready == 0
            redis.set("vmpooler__empty__#{pool_name}", 'true')
            $logger.log('s', "[!] [#{pool_name}] is empty")
          end
        end

        (pool_size - total.to_i).times do
          if redis.get('vmpooler__tasks__clone').to_i < $config[:config]['task_limit'].to_i
            begin
              redis.incr('vmpooler__tasks__clone')
              pool_check_response[:cloned_vms] += 1
              clone_vm(pool_name, provider, dns_plugin)
            rescue StandardError => e
              $logger.log('s', "[!] [#{pool_name}] clone failed during check_pool with an error: #{e}")
              redis.decr('vmpooler__tasks__clone')
              raise
            end
          end
        end
      end
    end

    def _check_pool(pool, provider)
      pool_check_response = {
        discovered_vms: 0,
        checked_running_vms: 0,
        checked_ready_vms: 0,
        checked_pending_vms: 0,
        destroyed_vms: 0,
        migrated_vms: 0,
        cloned_vms: 0
      }

      begin
        inventory = create_inventory(pool, provider, pool_check_response)
      rescue StandardError
        return(pool_check_response)
      end

      check_running_pool_vms(pool['name'], provider, pool_check_response, inventory)

      check_ready_pool_vms(pool['name'], provider, pool_check_response, inventory, pool['ready_ttl'] || $config[:config]['ready_ttl'])

      check_pending_pool_vms(pool['name'], provider, pool_check_response, inventory, pool['timeout'], pool['timeout_notification'])

      check_completed_pool_vms(pool['name'], provider, pool_check_response, inventory)

      check_discovered_pool_vms(pool['name'])

      check_migrating_pool_vms(pool['name'], provider, pool_check_response, inventory)

      # UPDATE TEMPLATE
      # Evaluates a pool template to ensure templates are prepared adequately for the configured provider
      # If a pool template configuration change is detected then template preparation is repeated for the new template
      # Additionally, a pool will drain ready and pending instances
      evaluate_template(pool, provider)

      # Check to see if a pool size change has been made via the configuration API
      # Since check_pool runs in a loop it does not
      # otherwise identify this change when running
      update_pool_size(pool)

      # Check to see if a pool size change has been made via the configuration API
      # Additionally, a pool will drain ready and pending instances
      update_clone_target(pool)

      repopulate_pool_vms(pool['name'], provider, pool_check_response, pool['size'])

      # Remove VMs in excess of the configured pool size
      remove_excess_vms(pool)

      # Reset a pool when poolreset is requested from the API
      reset_pool(pool)

      # Undo overrides submitted via the api
      undo_override(pool, provider)

      pool_check_response
    end

    # Create a provider object, usually based on the providers/*.rb class, that implements providers/base.rb
    # provider_class: Needs to match a class in the Vmpooler::PoolManager::Provider namespace. This is
    #                 either as a gem in the LOADPATH or in providers/*.rb ie Vmpooler::PoolManager::Provider::X
    # provider_name:  Should be a unique provider name
    #
    # returns an object Vmpooler::PoolManager::Provider::*
    # or raises an error if the class does not exist
    def create_provider_object(config, logger, metrics, redis_connection_pool, provider_class, provider_name, options)
      provider_klass = Vmpooler::PoolManager::Provider
      provider_klass.constants.each do |classname|
        next unless classname.to_s.casecmp(provider_class) == 0

        return provider_klass.const_get(classname).new(config, logger, metrics, redis_connection_pool, provider_name, options)
      end
      raise("Provider '#{provider_class}' is unknown for pool with provider name '#{provider_name}'") if provider_klass.nil?
    end

    def create_dns_object(config, logger, metrics, redis_connection_pool, dns_class, dns_name, options)
      if defined?(Vmpooler::PoolManager::Dns)
        dns_klass = Vmpooler::PoolManager::Dns
        dns_klass.constants.each do |classname|
          next unless classname.to_s.casecmp(dns_class) == 0

          return dns_klass.const_get(classname).new(config, logger, metrics, redis_connection_pool, dns_name, options)
        end
        raise("DNS '#{dns_class}' is unknown for pool with dns name '#{dns_name}'") if dns_klass.nil?
      end
    end

    def check_ondemand_requests(maxloop = 0,
                                loop_delay_min = CHECK_LOOP_DELAY_MIN_DEFAULT,
                                loop_delay_max = CHECK_LOOP_DELAY_MAX_DEFAULT,
                                loop_delay_decay = CHECK_LOOP_DELAY_DECAY_DEFAULT)

      $logger.log('d', '[*] [ondemand_provisioner] starting worker thread')

      $threads['ondemand_provisioner'] = Thread.new do
        _check_ondemand_requests(maxloop, loop_delay_min, loop_delay_max, loop_delay_decay)
      end
    end

    def _check_ondemand_requests(maxloop = 0,
                                 loop_delay_min = CHECK_LOOP_DELAY_MIN_DEFAULT,
                                 loop_delay_max = CHECK_LOOP_DELAY_MAX_DEFAULT,
                                 loop_delay_decay = CHECK_LOOP_DELAY_DECAY_DEFAULT)

      loop_delay_min = $config[:config]['check_loop_delay_min'] unless $config[:config]['check_loop_delay_min'].nil?
      loop_delay_max = $config[:config]['check_loop_delay_max'] unless $config[:config]['check_loop_delay_max'].nil?
      loop_delay_decay = $config[:config]['check_loop_delay_decay'] unless $config[:config]['check_loop_delay_decay'].nil?

      loop_delay_decay = 2.0 if loop_delay_decay <= 1.0
      loop_delay_max = loop_delay_min if loop_delay_max.nil? || loop_delay_max < loop_delay_min

      loop_count = 1
      loop_delay = loop_delay_min

      loop do
        result = process_ondemand_requests

        loop_delay = (loop_delay * loop_delay_decay).to_i
        loop_delay = loop_delay_min if result > 0
        loop_delay = loop_delay_max if loop_delay > loop_delay_max
        sleep_with_wakeup_events(loop_delay, loop_delay_min, ondemand_request: true)

        unless maxloop == 0
          break if loop_count >= maxloop

          loop_count += 1
        end
      end
    end

    def process_ondemand_requests
      @redis.with_metrics do |redis|
        requests = redis.zrange('vmpooler__provisioning__request', 0, -1)
        requests&.map { |request_id| create_ondemand_vms(request_id, redis) }
        provisioning_tasks = process_ondemand_vms(redis)
        requests_ready = check_ondemand_requests_ready(redis)
        requests.length + provisioning_tasks + requests_ready
      end
    end

    def create_ondemand_vms(request_id, redis)
      requested = redis.hget("vmpooler__odrequest__#{request_id}", 'requested')
      unless requested
        $logger.log('s', "Failed to find odrequest for request_id '#{request_id}'")
        redis.zrem('vmpooler__provisioning__request', request_id)
        return
      end
      score = redis.zscore('vmpooler__provisioning__request', request_id)
      requested = requested.split(',')

      redis.pipelined do |pipeline|
        requested.each do |request|
          pipeline.zadd('vmpooler__odcreate__task', Time.now.to_i, "#{request}:#{request_id}")
        end
        pipeline.zrem('vmpooler__provisioning__request', request_id)
        pipeline.zadd('vmpooler__provisioning__processing', score, request_id)
      end
    end

    def process_ondemand_vms(redis)
      queue_key = 'vmpooler__odcreate__task'
      queue = redis.zrange(queue_key, 0, -1, with_scores: true)
      ondemand_clone_limit = $config[:config]['ondemand_clone_limit']
      queue.each do |request, score|
        clone_count = redis.get('vmpooler__tasks__ondemandclone').to_i
        break unless clone_count < ondemand_clone_limit

        pool_alias, pool, count, request_id = request.split(':')
        count = count.to_i
        provider = get_provider_for_pool(pool)
        dns_plugin = get_dns_plugin_class_for_pool(pool)
        slots = ondemand_clone_limit - clone_count
        break if slots == 0

        if slots >= count
          count.times do
            redis.incr('vmpooler__tasks__ondemandclone')
            clone_vm(pool, provider, dns_plugin, request_id, pool_alias)
          end
          redis.zrem(queue_key, request)
        else
          remaining_count = count - slots
          slots.times do
            redis.incr('vmpooler__tasks__ondemandclone')
            clone_vm(pool, provider, dns_plugin, request_id, pool_alias)
          end
          redis.pipelined do |pipeline|
            pipeline.zrem(queue_key, request)
            pipeline.zadd(queue_key, score, "#{pool_alias}:#{pool}:#{remaining_count}:#{request_id}")
          end
        end
      end
      queue.length
    end

    def vms_ready?(request_id, redis)
      catch :request_not_ready do
        request_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
        Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, count|
          pools_filled = redis.scard("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
          throw :request_not_ready unless pools_filled.to_i == count.to_i
        end
        return true
      end
      false
    end

    def check_ondemand_requests_ready(redis)
      in_progress_requests = redis.zrange('vmpooler__provisioning__processing', 0, -1, with_scores: true)
      in_progress_requests&.each do |request_id, score|
        check_ondemand_request_ready(request_id, redis, score)
      end
      in_progress_requests.length
    end

    def check_ondemand_request_ready(request_id, redis, score = nil)
      # default expiration is one month to ensure the data does not stay in redis forever
      default_expiration = 259_200_0
      processing_key = 'vmpooler__provisioning__processing'
      ondemand_hash_key = "vmpooler__odrequest__#{request_id}"
      score ||= redis.zscore(processing_key, request_id)
      return if request_expired?(request_id, score, redis)

      return unless vms_ready?(request_id, redis)

      redis.hset(ondemand_hash_key, 'status', 'ready')
      redis.expire(ondemand_hash_key, default_expiration)
      redis.zrem(processing_key, request_id)
    end

    def request_expired?(request_id, score, redis)
      delta = Time.now.to_i - score.to_i
      ondemand_request_ttl = $config[:config]['ondemand_request_ttl']
      return false unless delta > ondemand_request_ttl * 60

      $logger.log('s', "Ondemand request for '#{request_id}' failed to provision all instances within the configured ttl '#{ondemand_request_ttl}'")
      expiration_ttl = $config[:redis]['data_ttl'].to_i * 60 * 60
      redis.pipelined do |pipeline|
        pipeline.zrem('vmpooler__provisioning__processing', request_id)
        pipeline.hset("vmpooler__odrequest__#{request_id}", 'status', 'failed')
        pipeline.expire("vmpooler__odrequest__#{request_id}", expiration_ttl)
      end
      remove_vms_for_failed_request(request_id, expiration_ttl, redis)
      true
    end

    def remove_vms_for_failed_request(request_id, expiration_ttl, redis)
      request_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
      Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, _count|
        pools_filled = redis.smembers("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
        redis.pipelined do |pipeline|
          pools_filled&.each do |vm|
            move_vm_queue(pool, vm, 'running', 'completed', pipeline, "moved to completed queue. '#{request_id}' could not be filled in time")
          end
          pipeline.expire("vmpooler__#{request_id}__#{platform_alias}__#{pool}", expiration_ttl)
        end
      end
    end

    def execute!(maxloop = 0, loop_delay = 1)
      $logger.log('d', 'starting vmpooler')

      @redis.with_metrics do |redis|
        # Clear out the tasks manager, as we don't know about any tasks at this point
        redis.set('vmpooler__tasks__clone', 0)
        redis.set('vmpooler__tasks__ondemandclone', 0)
        # Clear out vmpooler__migrations since stale entries may be left after a restart
        redis.del('vmpooler__migration')
      end

      # Copy vSphere settings to correct location.  This happens with older configuration files
      if !$config[:vsphere].nil? && ($config[:providers].nil? || $config[:providers][:vsphere].nil?)
        $logger.log('d', "[!] Detected an older configuration file. Copying the settings from ':vsphere:' to ':providers:/:vsphere:'")
        $config[:providers] = {} if $config[:providers].nil?
        $config[:providers][:vsphere] = $config[:vsphere]
      end

      # Set default provider for all pools that do not have one defined
      $config[:pools].each do |pool|
        if pool['provider'].nil?
          $logger.log('d', "[!] Setting provider for pool '#{pool['name']}' to 'dummy' as default")
          pool['provider'] = 'dummy'
        end
      end

      # Load running pool configuration into redis so API server can retrieve it
      load_pools_to_redis

      # Get pool loop settings
      $config[:config] = {} if $config[:config].nil?
      check_loop_delay_min = $config[:config]['check_loop_delay_min'] || CHECK_LOOP_DELAY_MIN_DEFAULT
      check_loop_delay_max = $config[:config]['check_loop_delay_max'] || CHECK_LOOP_DELAY_MAX_DEFAULT
      check_loop_delay_decay = $config[:config]['check_loop_delay_decay'] || CHECK_LOOP_DELAY_DECAY_DEFAULT

      # Create the providers
      $config[:pools].each do |pool|
        provider_name = pool['provider']
        dns_plugin_name = pool['dns_plugin']
        # The provider_class parameter can be defined in the provider's data eg
        # :providers:
        #   :vsphere:
        #     provider_class: 'vsphere'
        #   :another-vsphere:
        #     provider_class: 'vsphere'
        # the above would create two providers/vsphere.rb class objects named 'vsphere' and 'another-vsphere'
        # each pools would then define which provider definition to use: vsphere or another-vsphere
        #
        # if provider_class is not defined it will try to use the provider_name as the class, this is to be
        # backwards compatible for example when there is only one provider listed
        # :providers:
        #   :dummy:
        #     filename: 'db.txs'
        # the above example would create an object based on the class providers/dummy.rb
        if $config[:providers].nil? || $config[:providers][provider_name.to_sym].nil? || $config[:providers][provider_name.to_sym]['provider_class'].nil?
          provider_class = provider_name
        else
          provider_class = $config[:providers][provider_name.to_sym]['provider_class']
        end

        begin
          $providers[provider_name] = create_provider_object($config, $logger, $metrics, @redis, provider_class, provider_name, {}) if $providers[provider_name].nil?
        rescue StandardError => e
          $logger.log('s', "Error while creating provider for pool #{pool['name']}: #{e}")
          raise
        end

        dns_plugin_class = $config[:dns_configs][dns_plugin_name.to_sym]['dns_class']

        begin
          $dns_plugins[dns_plugin_class] = create_dns_object($config, $logger, $metrics, @redis, dns_plugin_class, dns_plugin_name, {}) if $dns_plugins[dns_plugin_class].nil?
        rescue StandardError => e
          $logger.log('s', "Error while creating dns plugin for pool #{pool['name']}: #{e}")
          raise
        end
      end

      purge_unused_vms_and_resources

      loop_count = 1
      loop do
        if !$threads['disk_manager']
          check_disk_queue
        elsif !$threads['disk_manager'].alive?
          $logger.log('d', '[!] [disk_manager] worker thread died, restarting')
          check_disk_queue
        end

        if !$threads['snapshot_manager']
          check_snapshot_queue
        elsif !$threads['snapshot_manager'].alive?
          $logger.log('d', '[!] [snapshot_manager] worker thread died, restarting')
          check_snapshot_queue
        end

        $config[:pools].each do |pool|
          if !$threads[pool['name']]
            check_pool(pool)
          elsif !$threads[pool['name']].alive?
            $logger.log('d', "[!] [#{pool['name']}] worker thread died, restarting")
            check_pool(pool, check_loop_delay_min, check_loop_delay_max, check_loop_delay_decay)
          end
        end

        if !$threads['ondemand_provisioner']
          check_ondemand_requests
        elsif !$threads['ondemand_provisioner'].alive?
          $logger.log('d', '[!] [ondemand_provisioner] worker thread died, restarting')
          check_ondemand_requests(check_loop_delay_min, check_loop_delay_max, check_loop_delay_decay)
        end

        # Queue purge thread
        if purge_enabled?
          purge_interval = ($config[:config] && $config[:config]['purge_interval']) || 3600 # default 1 hour
          if !$threads['queue_purge']
            $threads['queue_purge'] = Thread.new do
              loop do
                purge_stale_queue_entries
                sleep(purge_interval)
              end
            end
          elsif !$threads['queue_purge'].alive?
            $logger.log('d', '[!] [queue_purge] worker thread died, restarting')
            $threads['queue_purge'] = Thread.new do
              loop do
                purge_stale_queue_entries
                sleep(purge_interval)
              end
            end
          end
        end

        # Health check thread
        if health_check_enabled?
          health_interval = ($config[:config] && $config[:config]['health_check_interval']) || 300 # default 5 minutes
          if !$threads['health_check']
            $threads['health_check'] = Thread.new do
              loop do
                check_queue_health
                sleep(health_interval)
              end
            end
          elsif !$threads['health_check'].alive?
            $logger.log('d', '[!] [health_check] worker thread died, restarting')
            $threads['health_check'] = Thread.new do
              loop do
                check_queue_health
                sleep(health_interval)
              end
            end
          end
        end

        sleep(loop_delay)

        unless maxloop == 0
          break if loop_count >= maxloop

          loop_count += 1
        end
      end
    rescue Redis::CannotConnectError => e
      $logger.log('s', "Cannot connect to the redis server: #{e}")
      raise
    end
  end
end
