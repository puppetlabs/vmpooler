# frozen_string_literal: true

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

      # Our thread-tracker object
      $threads = Concurrent::Hash.new

      # Pool mutex
      @reconfigure_pool = Concurrent::Hash.new

      @vm_mutex = Concurrent::Hash.new

      # Name generator for generating host names
      @name_generator = Spicy::Proton.new

      # load specified providers from config file
      load_used_providers
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
          redis.sadd('vmpooler__pools', pool['name'])
          pool_keys = pool.keys
          pool_keys.delete('alias')
          to_set = {}
          pool_keys.each do |k|
            to_set[k] = pool[k]
          end
          to_set['alias'] = pool['alias'].join(',') if to_set.key?('alias')
          redis.hmset("vmpooler__pool__#{pool['name']}", to_set.to_a.flatten) unless to_set.empty?
        end
        previously_configured_pools.each do |pool|
          unless currently_configured_pools.include? pool
            redis.srem('vmpooler__pools', pool)
            redis.del("vmpooler__pool__#{pool}")
          end
        end
      end
      nil
    end

    # Check the state of a VM
    def check_pending_vm(vm, pool, timeout, provider)
      Thread.new do
        begin
          _check_pending_vm(vm, pool, timeout, provider)
        rescue StandardError => e
          $logger.log('s', "[!] [#{pool}] '#{vm}' #{timeout} #{provider} errored while checking a pending vm : #{e}")
          @redis.with_metrics do |redis|
            fail_pending_vm(vm, pool, timeout, redis)
          end
          raise
        end
      end
    end

    def _check_pending_vm(vm, pool, timeout, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        @redis.with_metrics do |redis|
          request_id = redis.hget("vmpooler__vm__#{vm}", 'request_id')
          if provider.vm_ready?(pool, vm)
            move_pending_vm_to_ready(vm, pool, redis, request_id)
          else
            fail_pending_vm(vm, pool, timeout, redis)
          end
        end
      end
    end

    def remove_nonexistent_vm(vm, pool, redis)
      redis.srem("vmpooler__pending__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    def fail_pending_vm(vm, pool, timeout, redis, exists: true)
      clone_stamp = redis.hget("vmpooler__vm__#{vm}", 'clone')

      time_since_clone = (Time.now - Time.parse(clone_stamp)) / 60
      if time_since_clone > timeout
        if exists
          request_id = redis.hget("vmpooler__vm__#{vm}", 'request_id')
          pool_alias = redis.hget("vmpooler__vm__#{vm}", 'pool_alias') if request_id
          redis.multi
          redis.smove("vmpooler__pending__#{pool}", "vmpooler__completed__#{pool}", vm)
          redis.zadd('vmpooler__odcreate__task', 1, "#{pool_alias}:#{pool}:1:#{request_id}") if request_id
          redis.exec
          $metrics.increment("errors.markedasfailed.#{pool}")
          $logger.log('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
        else
          remove_nonexistent_vm(vm, pool, redis)
        end
      end
      true
    rescue StandardError => e
      $logger.log('d', "Fail pending VM failed with an error: #{e}")
      false
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

        redis.pipelined do
          redis.hset("vmpooler__active__#{pool}", vm, Time.now)
          redis.hset("vmpooler__vm__#{vm}", 'checkout', Time.now)
          if ondemandrequest_hash['token:token']
            redis.hset("vmpooler__vm__#{vm}", 'token:token', ondemandrequest_hash['token:token'])
            redis.hset("vmpooler__vm__#{vm}", 'token:user', ondemandrequest_hash['token:user'])
            redis.hset("vmpooler__vm__#{vm}", 'lifetime', $config[:config]['vm_lifetime_auth'].to_i)
          end
          redis.sadd("vmpooler__#{request_id}__#{pool_alias}__#{pool}", vm)
        end
        move_vm_queue(pool, vm, 'pending', 'running', redis)
        check_ondemand_request_ready(request_id, redis)
      else
        redis.smove("vmpooler__pending__#{pool}", "vmpooler__ready__#{pool}", vm)
      end

      redis.pipelined do
        redis.hset("vmpooler__boot__#{Date.today}", "#{pool}:#{vm}", finish) # maybe remove as this is never used by vmpooler itself?
        redis.hset("vmpooler__vm__#{vm}", 'ready', Time.now)

        # last boot time is displayed in API, and used by alarming script
        redis.hset('vmpooler__lastboot', pool, Time.now)
      end

      $metrics.timing("time_to_ready_state.#{pool}", finish)
      $logger.log('s', "[>] [#{pool}] '#{vm}' moved from 'pending' to 'ready' queue") unless request_id
      $logger.log('s', "[>] [#{pool}] '#{vm}' is 'ready' for request '#{request_id}'") if request_id
    end

    def vm_still_ready?(pool_name, vm_name, provider, redis)
      # Check if the VM is still ready/available
      return true if provider.vm_ready?(pool_name, vm_name)

      raise("VM #{vm_name} is not ready")
    rescue StandardError
      move_vm_queue(pool_name, vm_name, 'ready', 'completed', redis, "is unreachable, removed from 'ready' queue")
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

          redis.hset("vmpooler__vm__#{vm}", 'check', Time.now)
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

            throw :stop_checking if provider.vm_ready?(pool, vm)

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

    # Clone a VM
    def clone_vm(pool_name, provider, request_id = nil, pool_alias = nil)
      Thread.new do
        begin
          _clone_vm(pool_name, provider, request_id, pool_alias)
        rescue StandardError => e
          if request_id
            $logger.log('s', "[!] [#{pool_name}] failed while cloning VM for request #{request_id} with an error: #{e}")
            @redis.with_metrics do |redis|
              redis.zadd('vmpooler__odcreate__task', 1, "#{pool_alias}:#{pool_name}:1:#{request_id}")
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
        domain = $config[:config]['domain']
        dns_ip, dns_available = check_dns_available(hostname, domain)
        break if hostname_available && dns_available

        hostname_retries += 1

        if !hostname_available
          $metrics.increment("errors.duplicatehostname.#{pool_name}")
          $logger.log('s', "[!] [#{pool_name}] Generated hostname #{hostname} was not unique (attempt \##{hostname_retries} of #{max_hostname_retries})")
        elsif !dns_available
          $metrics.increment("errors.staledns.#{pool_name}")
          $logger.log('s', "[!] [#{pool_name}] Generated hostname #{hostname} already exists in DNS records (#{dns_ip}), stale DNS")
        end
      end

      raise "Unable to generate a unique hostname after #{hostname_retries} attempts. The last hostname checked was #{hostname}" unless hostname_available && dns_available

      hostname
    end

    def check_dns_available(vm_name, domain = nil)
      # Query the DNS for the name we want to create and if it already exists, mark it unavailable
      # This protects against stale DNS records
      vm_name = "#{vm_name}.#{domain}" if domain
      begin
        dns_ip = Resolv.getaddress(vm_name)
      rescue Resolv::ResolvError
        # this is the expected case, swallow the error
        # eg "no address for blah-daisy"
        return ['', true]
      end
      [dns_ip, false]
    end

    def _clone_vm(pool_name, provider, request_id = nil, pool_alias = nil)
      new_vmname = find_unique_hostname(pool_name)
      mutex = vm_mutex(new_vmname)
      mutex.synchronize do
        @redis.with_metrics do |redis|
          # Add VM to Redis inventory ('pending' pool)
          redis.multi
          redis.sadd("vmpooler__pending__#{pool_name}", new_vmname)
          redis.hset("vmpooler__vm__#{new_vmname}", 'clone', Time.now)
          redis.hset("vmpooler__vm__#{new_vmname}", 'template', pool_name) # This value is used to represent the pool.
          redis.hset("vmpooler__vm__#{new_vmname}", 'pool', pool_name)
          redis.hset("vmpooler__vm__#{new_vmname}", 'request_id', request_id) if request_id
          redis.hset("vmpooler__vm__#{new_vmname}", 'pool_alias', pool_alias) if pool_alias
          redis.exec
        end

        begin
          $logger.log('d', "[ ] [#{pool_name}] Starting to clone '#{new_vmname}'")
          start = Time.now
          provider.create_vm(pool_name, new_vmname)
          finish = format('%<time>.2f', time: Time.now - start)

          @redis.with_metrics do |redis|
            redis.pipelined do
              redis.hset("vmpooler__clone__#{Date.today}", "#{pool_name}:#{new_vmname}", finish)
              redis.hset("vmpooler__vm__#{new_vmname}", 'clone_time', finish)
            end
          end
          $logger.log('s', "[+] [#{pool_name}] '#{new_vmname}' cloned in #{finish} seconds")

          $metrics.timing("clone.#{pool_name}", finish)
        rescue StandardError
          @redis.with_metrics do |redis|
            redis.pipelined do
              redis.srem("vmpooler__pending__#{pool_name}", new_vmname)
              expiration_ttl = $config[:redis]['data_ttl'].to_i * 60 * 60
              redis.expire("vmpooler__vm__#{new_vmname}", expiration_ttl)
            end
          end
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
    def destroy_vm(vm, pool, provider)
      Thread.new do
        begin
          _destroy_vm(vm, pool, provider)
        rescue StandardError => e
          $logger.log('d', "[!] [#{pool}] '#{vm}' failed while destroying the VM with an error: #{e}")
          raise
        end
      end
    end

    def _destroy_vm(vm, pool, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?

      mutex.synchronize do
        @redis.with_metrics do |redis|
          redis.pipelined do
            redis.hdel("vmpooler__active__#{pool}", vm)
            redis.hset("vmpooler__vm__#{vm}", 'destroy', Time.now)

            # Auto-expire metadata key
            redis.expire("vmpooler__vm__#{vm}", ($config[:redis]['data_ttl'].to_i * 60 * 60))
          end

          start = Time.now

          provider.destroy_vm(pool, vm)

          redis.srem("vmpooler__completed__#{pool}", vm)

          finish = format('%<time>.2f', time: Time.now - start)
          $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
          $metrics.timing("destroy.#{pool}", finish)
        end
      end
      dereference_mutex(vm)
    end

    def purge_unused_vms_and_folders
      global_purge = $config[:config]['purge_unconfigured_folders']
      providers = $config[:providers].keys
      providers.each do |provider_key|
        provider_purge = $config[:providers][provider_key]['purge_unconfigured_folders'] || global_purge
        if provider_purge
          Thread.new do
            begin
              purge_vms_and_folders(provider_key)
            rescue StandardError => e
              $logger.log('s', "[!] failed while purging provider #{provider_key} VMs and folders with an error: #{e}")
            end
          end
        end
      end
      nil
    end

    # Return a list of pool folders
    def pool_folders(provider_name)
      folders = {}
      $config[:pools].each do |pool|
        next unless pool['provider'] == provider_name.to_s

        folder_parts = pool['folder'].split('/')
        datacenter = $providers[provider_name.to_s].get_target_datacenter_from_config(pool['name'])
        folders[folder_parts.pop] = "#{datacenter}/vm/#{folder_parts.join('/')}"
      end
      folders
    end

    def get_base_folders(folders)
      base = []
      folders.each do |_key, value|
        base << value
      end
      base.uniq
    end

    def purge_vms_and_folders(provider_name)
      provider = $providers[provider_name.to_s]
      configured_folders = pool_folders(provider_name)
      base_folders = get_base_folders(configured_folders)
      whitelist = provider.provider_config['folder_whitelist']
      provider.purge_unconfigured_folders(base_folders, configured_folders, whitelist)
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

    # load only providers used in config file
    def load_used_providers
      Vmpooler::Providers.load_by_name(used_providers)
    end

    # @return [Array] - a list of used providers from the config file, defaults to the default providers
    # ie. ["vsphere", "dummy"]
    def used_providers
      pools = config[:pools] || []
      @used_providers ||= (pools.map { |pool| pool[:provider] || pool['provider'] }.compact + default_providers).uniq
    end

    # @return [Array] - returns a list of providers that should always be loaded
    # note: vsphere is the default if user does not specify although this should not be
    # if vsphere is to no longer be loaded by default please remove
    def default_providers
      @default_providers ||= %w[vsphere dummy]
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
    #
    def sleep_with_wakeup_events(loop_delay, wakeup_period = 5, options = {})
      exit_by = Time.now + loop_delay
      wakeup_by = Time.now + wakeup_period
      return if time_passed?(:exit_by, exit_by)

      @redis.with_metrics do |redis|
        initial_ready_size = redis.scard("vmpooler__ready__#{options[:poolname]}") if options[:pool_size_change]

        initial_clone_target = redis.hget("vmpooler__pool__#{options[:poolname]}", options[:clone_target]) if options[:clone_target_change]

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

            if options[:pending_vm]
              pending_vm_count = redis.scard("vmpooler__pending__#{options[:poolname]}")
              break unless pending_vm_count == 0
            end

            if options[:ondemand_request]
              redis.multi
              redis.zcard('vmpooler__provisioning__request')
              redis.zcard('vmpooler__provisioning__processing')
              redis.zcard('vmpooler__odcreate__task')
              od_request, od_processing, od_createtask = redis.exec
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
          raise("Could not find provider '#{pool['provider']}") if provider.nil?

          sync_pool_template(pool)
          loop do
            result = _check_pool(pool, provider)

            if result[:cloned_vms] > 0 || result[:checked_pending_vms] > 0 || result[:discovered_vms] > 0
              loop_delay = loop_delay_min
            else
              loop_delay = (loop_delay * loop_delay_decay).to_i
              loop_delay = loop_delay_max if loop_delay > loop_delay_max
            end
            sleep_with_wakeup_events(loop_delay, loop_delay_min, pool_size_change: true, poolname: pool['name'], pool_template_change: true, clone_target_change: true, pending_vm: true, pool_reset: true)

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
        redis.multi
        redis.scard("vmpooler__ready__#{pool['name']}")
        redis.scard("vmpooler__pending__#{pool['name']}")
        ready, pending = redis.exec
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
        poolsize = redis.hget('vmpooler__config__poolsize', pool['name'])
        break if poolsize.nil?

        poolsize = Integer(poolsize)
        break if poolsize == pool['size']

        mutex.synchronize do
          pool['size'] = poolsize
        end
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

    def check_pending_pool_vms(pool_name, provider, pool_check_response, inventory, pool_timeout)
      pool_timeout ||= $config[:config]['timeout'] || 15
      @redis.with_metrics do |redis|
        redis.smembers("vmpooler__pending__#{pool_name}").reverse.each do |vm|
          if inventory[vm]
            begin
              pool_check_response[:checked_pending_vms] += 1
              check_pending_vm(vm, pool_name, pool_timeout, provider)
            rescue StandardError => e
              $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating pending VMs: #{e}")
            end
          else
            fail_pending_vm(vm, pool_name, pool_timeout, redis, exists: false)
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
              destroy_vm(vm, pool_name, provider)
            rescue StandardError => e
              redis.pipelined do
                redis.srem("vmpooler__completed__#{pool_name}", vm)
                redis.hdel("vmpooler__active__#{pool_name}", vm)
                redis.del("vmpooler__vm__#{vm}")
              end
              $logger.log('d', "[!] [#{pool_name}] _check_pool failed with an error while evaluating completed VMs: #{e}")
            end
          else
            $logger.log('s', "[!] [#{pool_name}] '#{vm}' not found in inventory, removed from 'completed' queue")
            redis.pipelined do
              redis.srem("vmpooler__completed__#{pool_name}", vm)
              redis.hdel("vmpooler__active__#{pool_name}", vm)
              redis.del("vmpooler__vm__#{vm}")
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
        redis.multi
        redis.scard("vmpooler__ready__#{pool_name}")
        redis.scard("vmpooler__pending__#{pool_name}")
        redis.scard("vmpooler__running__#{pool_name}")
        ready, pending, running = redis.exec
        total = pending.to_i + ready.to_i

        $metrics.gauge("ready.#{pool_name}", ready)
        $metrics.gauge("running.#{pool_name}", running)

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
              clone_vm(pool_name, provider)
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

      check_pending_pool_vms(pool['name'], provider, pool_check_response, inventory, pool['timeout'])

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
      raise("Provider '#{provider_class}' is unknown for pool with provider name '#{provider_name}'") if provider.nil?
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

      redis.pipelined do
        requested.each do |request|
          redis.zadd('vmpooler__odcreate__task', Time.now.to_i, "#{request}:#{request_id}")
        end
        redis.zrem('vmpooler__provisioning__request', request_id)
        redis.zadd('vmpooler__provisioning__processing', score, request_id)
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
        slots = ondemand_clone_limit - clone_count
        break if slots == 0

        if slots >= count
          count.times do
            redis.incr('vmpooler__tasks__ondemandclone')
            clone_vm(pool, provider, request_id, pool_alias)
          end
          redis.zrem(queue_key, request)
        else
          remaining_count = count - slots
          slots.times do
            redis.incr('vmpooler__tasks__ondemandclone')
            clone_vm(pool, provider, request_id, pool_alias)
          end
          redis.pipelined do
            redis.zrem(queue_key, request)
            redis.zadd(queue_key, score, "#{pool_alias}:#{pool}:#{remaining_count}:#{request_id}")
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

      redis.multi
      redis.hset(ondemand_hash_key, 'status', 'ready')
      redis.expire(ondemand_hash_key, default_expiration)
      redis.zrem(processing_key, request_id)
      redis.exec
    end

    def request_expired?(request_id, score, redis)
      delta = Time.now.to_i - score.to_i
      ondemand_request_ttl = $config[:config]['ondemand_request_ttl']
      return false unless delta > ondemand_request_ttl * 60

      $logger.log('s', "Ondemand request for '#{request_id}' failed to provision all instances within the configured ttl '#{ondemand_request_ttl}'")
      expiration_ttl = $config[:redis]['data_ttl'].to_i * 60 * 60
      redis.pipelined do
        redis.zrem('vmpooler__provisioning__processing', request_id)
        redis.hset("vmpooler__odrequest__#{request_id}", 'status', 'failed')
        redis.expire("vmpooler__odrequest__#{request_id}", expiration_ttl)
      end
      remove_vms_for_failed_request(request_id, expiration_ttl, redis)
      true
    end

    def remove_vms_for_failed_request(request_id, expiration_ttl, redis)
      request_hash = redis.hgetall("vmpooler__odrequest__#{request_id}")
      Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, _count|
        pools_filled = redis.smembers("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
        redis.pipelined do
          pools_filled&.each do |vm|
            move_vm_queue(pool, vm, 'running', 'completed', redis, "moved to completed queue. '#{request_id}' could not be filled in time")
          end
          redis.expire("vmpooler__#{request_id}__#{platform_alias}__#{pool}", expiration_ttl)
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
          $logger.log('d', "[!] Setting provider for pool '#{pool['name']}' to 'vsphere' as default")
          pool['provider'] = 'vsphere'
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
        # The provider_class parameter can be defined in the provider's data eg
        #:providers:
        # :vsphere:
        #  provider_class: 'vsphere'
        # :another-vsphere:
        #  provider_class: 'vsphere'
        # the above would create two providers/vsphere.rb class objects named 'vsphere' and 'another-vsphere'
        # each pools would then define which provider definition to use: vsphere or another-vsphere
        #
        # if provider_class is not defined it will try to use the provider_name as the class, this is to be
        # backwards compatible for example when there is only one provider listed
        # :providers:
        #  :dummy:
        #   filename: 'db.txs'
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
      end

      purge_unused_vms_and_folders

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
