module Vmpooler
  class PoolManager
    CHECK_LOOP_DELAY_MIN_DEFAULT = 5
    CHECK_LOOP_DELAY_MAX_DEFAULT = 60
    CHECK_LOOP_DELAY_DECAY_DEFAULT = 2.0

    def initialize(config, logger, redis, metrics)
      $config = config

      # Load logger library
      $logger = logger

      # metrics logging handle
      $metrics = metrics

      # Connect to Redis
      $redis = redis

      # VM Provider objects
      $providers = {}

      # Our thread-tracker object
      $threads = {}

      # Pool mutex
      @reconfigure_pool = {}

      @vm_mutex = {}
    end

    def config
      $config
    end

    # Check the state of a VM
    def check_pending_vm(vm, pool, timeout, provider)
      Thread.new do
        begin
          _check_pending_vm(vm, pool, timeout, provider)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' #{timeout} #{provider} errored while checking a pending vm : #{err}")
          fail_pending_vm(vm, pool, timeout)
          raise
        end
      end
    end

    def _check_pending_vm(vm, pool, timeout, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?
      mutex.synchronize do
        host = provider.get_vm(pool, vm)
        unless host
          fail_pending_vm(vm, pool, timeout, false)
          return
        end
        if provider.vm_ready?(pool, vm)
          move_pending_vm_to_ready(vm, pool, host)
        else
          fail_pending_vm(vm, pool, timeout)
        end
      end
    end

    def remove_nonexistent_vm(vm, pool)
      $redis.srem("vmpooler__pending__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    def fail_pending_vm(vm, pool, timeout, exists = true)
      clone_stamp = $redis.hget("vmpooler__vm__#{vm}", 'clone')
      return true unless clone_stamp

      time_since_clone = (Time.now - Time.parse(clone_stamp)) / 60
      if time_since_clone > timeout
        if exists
          $redis.smove('vmpooler__pending__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
        else
          remove_nonexistent_vm(vm, pool)
        end
      end
      true
    rescue => err
      $logger.log('d', "Fail pending VM failed with an error: #{err}")
      false
    end

    def move_pending_vm_to_ready(vm, pool, host)
      if host['hostname'] == vm
        begin
          Socket.getaddrinfo(vm, nil) # WTF? I assume this is just priming the local DNS resolver cache?!?!
        rescue # rubocop:disable Lint/HandleExceptions
          # Do not care about errors what-so-ever
        end

        clone_time = $redis.hget('vmpooler__vm__' + vm, 'clone')
        finish = format('%.2f', Time.now - Time.parse(clone_time)) if clone_time

        $redis.smove('vmpooler__pending__' + pool, 'vmpooler__ready__' + pool, vm)
        $redis.hset('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm, finish) # maybe remove as this is never used by vmpooler itself?

        # last boot time is displayed in API, and used by alarming script
        $redis.hset('vmpooler__lastboot', pool, Time.now)

        $logger.log('s', "[>] [#{pool}] '#{vm}' moved from 'pending' to 'ready' queue")
      end
    end

    def check_ready_vm(vm, pool, ttl, provider)
      Thread.new do
        begin
          _check_ready_vm(vm, pool, ttl, provider)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' failed while checking a ready vm : #{err}")
          raise
        end
      end
    end

    def _check_ready_vm(vm, pool, ttl, provider)
      # Periodically check that the VM is available
      mutex = vm_mutex(vm)
      return if mutex.locked?
      mutex.synchronize do
        check_stamp = $redis.hget('vmpooler__vm__' + vm, 'check')
        return if check_stamp && (((Time.now - Time.parse(check_stamp)) / 60) <= $config[:config]['vm_checktime'])

        host = provider.get_vm(pool, vm)
        # Check if the host even exists
        unless host
          $redis.srem('vmpooler__ready__' + pool, vm)
          $logger.log('s', "[!] [#{pool}] '#{vm}' not found in inventory, removed from 'ready' queue")
          return
        end

        $redis.hset('vmpooler__vm__' + vm, 'check', Time.now)
        # Check if the VM is not powered on, before checking TTL
        unless host['powerstate'].casecmp('poweredon').zero?
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' appears to be powered off, removed from 'ready' queue")
          return
        end

        # Check if the hosts TTL has expired
        if ttl > 0
          # host['boottime'] may be nil if host is not powered on
          if ((Time.now - host['boottime']) / 60).to_s[/^\d+\.\d{1}/].to_f > ttl
            $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

            $logger.log('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
            return
          end
        end

        # Check if the hostname has magically changed from underneath Pooler
        if host['hostname'] != vm
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' has mismatched hostname, removed from 'ready' queue")
          return
        end

        # Check if the VM is still ready/available
        begin
          raise("VM #{vm} is not ready") unless provider.vm_ready?(pool, vm)
        rescue
          if $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
            $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")
          else
            $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, and failed to remove from 'ready' queue")
          end
        end
      end
    end

    def check_running_vm(vm, pool, ttl, provider)
      Thread.new do
        begin
          _check_running_vm(vm, pool, ttl, provider)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' failed while checking VM with an error: #{err}")
          raise
        end
      end
    end

    def _check_running_vm(vm, pool, ttl, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?
      mutex.synchronize do
        host = provider.get_vm(pool, vm)

        if host
          # Check that VM is within defined lifetime
          checkouttime = $redis.hget('vmpooler__active__' + pool, vm)
          if checkouttime
            running = (Time.now - Time.parse(checkouttime)) / 60 / 60

            if (ttl.to_i > 0) && (running.to_i >= ttl.to_i)
              move_vm_queue(pool, vm, 'running', 'completed', "reached end of TTL after #{ttl} hours")
            end
          end
        end
      end
    end

    def move_vm_queue(pool, vm, queue_from, queue_to, msg = nil)
      $redis.smove("vmpooler__#{queue_from}__#{pool}", "vmpooler__#{queue_to}__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' #{msg}") if msg
    end

    # Clone a VM
    def clone_vm(pool, provider)
      Thread.new do
        begin
          _clone_vm(pool, provider)
        rescue => err
          $logger.log('s', "[!] [#{pool['name']}] failed while cloning VM with an error: #{err}")
          raise
        end
      end
    end

    def _clone_vm(pool, provider)
      pool_name = pool['name']

      # Generate a randomized hostname
      o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
      new_vmname = $config[:config]['prefix'] + o[rand(25)] + (0...14).map { o[rand(o.length)] }.join

      # Add VM to Redis inventory ('pending' pool)
      $redis.sadd('vmpooler__pending__' + pool_name, new_vmname)
      $redis.hset('vmpooler__vm__' + new_vmname, 'clone', Time.now)
      $redis.hset('vmpooler__vm__' + new_vmname, 'template', pool_name)

      begin
        $logger.log('d', "[ ] [#{pool_name}] Starting to clone '#{new_vmname}'")
        start = Time.now
        provider.create_vm(pool_name, new_vmname)
        finish = format('%.2f', Time.now - start)

        $redis.hset('vmpooler__clone__' + Date.today.to_s, pool_name + ':' + new_vmname, finish)
        $redis.hset('vmpooler__vm__' + new_vmname, 'clone_time', finish)
        $logger.log('s', "[+] [#{pool_name}] '#{new_vmname}' cloned in #{finish} seconds")

        $metrics.timing("clone.#{pool_name}", finish)
      rescue => _err
        $redis.srem('vmpooler__pending__' + pool_name, new_vmname)
        raise _err
      ensure
        $redis.decr('vmpooler__tasks__clone')
      end
    end

    # Destroy a VM
    def destroy_vm(vm, pool, provider)
      Thread.new do
        begin
          _destroy_vm(vm, pool, provider)
        rescue => err
          $logger.log('d', "[!] [#{pool}] '#{vm}' failed while destroying the VM with an error: #{err}")
          raise
        end
      end
    end

    def _destroy_vm(vm, pool, provider)
      mutex = vm_mutex(vm)
      return if mutex.locked?
      mutex.synchronize do
        $redis.srem('vmpooler__completed__' + pool, vm)
        $redis.hdel('vmpooler__active__' + pool, vm)
        $redis.hset('vmpooler__vm__' + vm, 'destroy', Time.now)

        # Auto-expire metadata key
        $redis.expire('vmpooler__vm__' + vm, ($config[:redis]['data_ttl'].to_i * 60 * 60))

        start = Time.now

        provider.destroy_vm(pool, vm)

        finish = format('%.2f', Time.now - start)
        $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
        $metrics.timing("destroy.#{pool}", finish)
      end
    end

    def create_vm_disk(pool_name, vm, disk_size, provider)
      Thread.new do
        begin
          _create_vm_disk(pool_name, vm, disk_size, provider)
        rescue => err
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while creating disk: #{err}")
          raise
        end
      end
    end

    def _create_vm_disk(pool_name, vm_name, disk_size, provider)
      raise("Invalid disk size of '#{disk_size}' passed") if disk_size.nil? || disk_size.empty? || disk_size.to_i <= 0

      $logger.log('s', "[ ] [disk_manager] '#{vm_name}' is attaching a #{disk_size}gb disk")

      start = Time.now

      result = provider.create_disk(pool_name, vm_name, disk_size.to_i)

      finish = format('%.2f', Time.now - start)

      if result
        rdisks = $redis.hget('vmpooler__vm__' + vm_name, 'disk')
        disks = rdisks ? rdisks.split(':') : []
        disks.push("+#{disk_size}gb")
        $redis.hset('vmpooler__vm__' + vm_name, 'disk', disks.join(':'))

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
        rescue => err
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while creating snapshot: #{err}")
          raise
        end
      end
    end

    def _create_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
      $logger.log('s', "[ ] [snapshot_manager] 'Attempting to snapshot #{vm_name} in pool #{pool_name}")
      start = Time.now

      result = provider.create_snapshot(pool_name, vm_name, snapshot_name)

      finish = format('%.2f', Time.now - start)

      if result
        $redis.hset('vmpooler__vm__' + vm_name, 'snapshot:' + snapshot_name, Time.now.to_s)
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
        rescue => err
          $logger.log('d', "[!] [#{pool_name}] '#{vm}' failed while reverting snapshot: #{err}")
          raise
        end
      end
    end

    def _revert_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
      $logger.log('s', "[ ] [snapshot_manager] 'Attempting to revert #{vm_name}' in pool #{pool_name} to snapshot '#{snapshot_name}'")
      start = Time.now

      result = provider.revert_snapshot(pool_name, vm_name, snapshot_name)

      finish = format('%.2f', Time.now - start)

      if result
        $logger.log('s', "[+] [snapshot_manager] '#{vm_name}' reverted to snapshot '#{snapshot_name}' in #{finish} seconds")
      else
        $logger.log('s', "[+] [snapshot_manager] Failed to revert #{vm_name}' in pool #{pool_name} to snapshot '#{snapshot_name}'")
      end

      result
    end

    def get_pool_name_for_vm(vm_name)
      # the 'template' is a bad name.  Should really be 'poolname'
      $redis.hget('vmpooler__vm__' + vm_name, 'template')
    end

    def get_provider_for_pool(pool_name)
      provider_name = nil
      $config[:pools].each do |pool|
        next unless pool['name'] == pool_name
        provider_name = pool['provider']
      end
      return nil if provider_name.nil?

      $providers[provider_name]
    end

    def check_disk_queue(maxloop = 0, loop_delay = 5)
      $logger.log('d', '[*] [disk_manager] starting worker thread')

      $threads['disk_manager'] = Thread.new do
        loop_count = 1
        loop do
          _check_disk_queue
          sleep(loop_delay)

          unless maxloop.zero?
            break if loop_count >= maxloop
            loop_count += 1
          end
        end
      end
    end

    def _check_disk_queue
      task_detail = $redis.spop('vmpooler__tasks__disk')
      unless task_detail.nil?
        begin
          vm_name, disk_size = task_detail.split(':')
          pool_name = get_pool_name_for_vm(vm_name)
          raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

          provider = get_provider_for_pool(pool_name)
          raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

          create_vm_disk(pool_name, vm_name, disk_size, provider)
        rescue => err
          $logger.log('s', "[!] [disk_manager] disk creation appears to have failed: #{err}")
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

          unless maxloop.zero?
            break if loop_count >= maxloop
            loop_count += 1
          end
        end
      end
    end

    def _check_snapshot_queue
      task_detail = $redis.spop('vmpooler__tasks__snapshot')

      unless task_detail.nil?
        begin
          vm_name, snapshot_name = task_detail.split(':')
          pool_name = get_pool_name_for_vm(vm_name)
          raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

          provider = get_provider_for_pool(pool_name)
          raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

          create_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
        rescue => err
          $logger.log('s', "[!] [snapshot_manager] snapshot create appears to have failed: #{err}")
        end
      end

      task_detail = $redis.spop('vmpooler__tasks__snapshot-revert')

      unless task_detail.nil?
        begin
          vm_name, snapshot_name = task_detail.split(':')
          pool_name = get_pool_name_for_vm(vm_name)
          raise("Unable to determine which pool #{vm_name} is a member of") if pool_name.nil?

          provider = get_provider_for_pool(pool_name)
          raise("Missing Provider for vm #{vm_name} in pool #{pool_name}") if provider.nil?

          revert_vm_snapshot(pool_name, vm_name, snapshot_name, provider)
        rescue => err
          $logger.log('s', "[!] [snapshot_manager] snapshot revert appears to have failed: #{err}")
        end
      end
    end

    def migrate_vm(vm_name, pool_name, provider)
      Thread.new do
        begin
          mutex = vm_mutex(vm_name)
          mutex.synchronize do
            $redis.srem("vmpooler__migrating__#{pool_name}", vm_name)
            provider.migrate_vm(pool_name, vm_name)
          end
        rescue => err
          $logger.log('s', "[x] [#{pool_name}] '#{vm_name}' migration failed with an error: #{err}")
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
    #
    def sleep_with_wakeup_events(loop_delay, wakeup_period = 5, options = {})
      exit_by = Time.now + loop_delay
      wakeup_by = Time.now + wakeup_period
      return if time_passed?(:exit_by, exit_by)

      if options[:pool_size_change]
        initial_ready_size = $redis.scard("vmpooler__ready__#{options[:poolname]}")
      end

      if options[:pool_template_change]
        initial_template = $redis.hget('vmpooler__template__prepared', options[:poolname])
      end

      loop do
        sleep(1)
        break if time_passed?(:exit_by, exit_by)

        # Check for wakeup events
        if time_passed?(:wakeup_by, wakeup_by)
          wakeup_by = Time.now + wakeup_period

          # Wakeup if the number of ready VMs has changed
          if options[:pool_size_change]
            ready_size = $redis.scard("vmpooler__ready__#{options[:poolname]}")
            break unless ready_size == initial_ready_size
          end

          if options[:pool_template_change]
            configured_template = $redis.hget('vmpooler__config__template', options[:poolname])
            if configured_template
              break unless initial_template == configured_template
            end
          end

        end

        break if time_passed?(:exit_by, exit_by)
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
            sleep_with_wakeup_events(loop_delay, loop_delay_min, pool_size_change: true, poolname: pool['name'], pool_template_change: true)

            unless maxloop.zero?
              break if loop_count >= maxloop
              loop_count += 1
            end
          end
        rescue => err
          $logger.log('s', "[!] [#{pool['name']}] Error while checking the pool: #{err}")
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

    def sync_pool_template(pool)
      pool_template = $redis.hget('vmpooler__config__template', pool['name'])
      if pool_template
        unless pool['template'] == pool_template
          pool['template'] = pool_template
        end
      end
    end

    def prepare_template(pool, provider)
      provider.create_template_delta_disks(pool) if $config[:config]['create_template_delta_disks']
      $redis.hset('vmpooler__template__prepared', pool['name'], pool['template'])
    end

    def evaluate_template(pool, provider)
      mutex = pool_mutex(pool['name'])
      prepared_template = $redis.hget('vmpooler__template__prepared', pool['name'])
      configured_template = $redis.hget('vmpooler__config__template', pool['name'])
      return if mutex.locked?
      if prepared_template.nil?
        mutex.synchronize do
          prepare_template(pool, provider)
          prepared_template = $redis.hget('vmpooler__template__prepared', pool['name'])
        end
      end
      return if configured_template.nil?
      return if configured_template == prepared_template
      mutex.synchronize do
        update_pool_template(pool, provider, configured_template, prepared_template)
      end
    end

    def drain_pool(poolname)
      # Clear a pool of ready and pending instances
      if $redis.scard("vmpooler__ready__#{poolname}") > 0
        $logger.log('s', "[*] [#{poolname}] removing ready instances")
        $redis.smembers("vmpooler__ready__#{poolname}").each do |vm|
          move_vm_queue(poolname, vm, 'ready', 'completed')
        end
      end
      if $redis.scard("vmpooler__pending__#{poolname}") > 0
        $logger.log('s', "[*] [#{poolname}] removing pending instances")
        $redis.smembers("vmpooler__pending__#{poolname}").each do |vm|
          move_vm_queue(poolname, vm, 'pending', 'completed')
        end
      end
    end

    def update_pool_template(pool, provider, configured_template, prepared_template)
      pool['template'] = configured_template
      $logger.log('s', "[*] [#{pool['name']}] template updated from #{prepared_template} to #{configured_template}")
      # Remove all ready and pending VMs so new instances are created from the new template
      drain_pool(pool['name'])
      # Prepare template for deployment
      $logger.log('s', "[*] [#{pool['name']}] preparing pool template for deployment")
      prepare_template(pool, provider)
      $logger.log('s', "[*] [#{pool['name']}] is ready for use")
    end

    def remove_excess_vms(pool, provider, ready, total)
      return if total.nil?
      return if total == 0
      mutex = pool_mutex(pool['name'])
      return if mutex.locked?
      return unless ready > pool['size']
      mutex.synchronize do
        difference = ready - pool['size']
        difference.times do
          next_vm = $redis.spop("vmpooler__ready__#{pool['name']}")
          move_vm_queue(pool['name'], next_vm, 'ready', 'completed')
        end
        if total > ready
          $redis.smembers("vmpooler__pending__#{pool['name']}").each do |vm|
            move_vm_queue(pool['name'], vm, 'pending', 'completed')
          end
        end
      end
    end

    def update_pool_size(pool)
      mutex = pool_mutex(pool['name'])
      return if mutex.locked?
      poolsize = $redis.hget('vmpooler__config__poolsize', pool['name'])
      return if poolsize.nil?
      poolsize = Integer(poolsize)
      return if poolsize == pool['size']
      mutex.synchronize do
        pool['size'] = poolsize
      end
    end

    def create_inventory(pool, provider)
      inventory = {}
      begin
        provider.vms_in_pool(pool['name']).each do |vm|
          if !$redis.sismember('vmpooler__running__' + pool['name'], vm['name']) &&
             !$redis.sismember('vmpooler__ready__' + pool['name'], vm['name']) &&
             !$redis.sismember('vmpooler__pending__' + pool['name'], vm['name']) &&
             !$redis.sismember('vmpooler__completed__' + pool['name'], vm['name']) &&
             !$redis.sismember('vmpooler__discovered__' + pool['name'], vm['name']) &&
             !$redis.sismember('vmpooler__migrating__' + pool['name'], vm['name'])

            pool_check_response[:discovered_vms] += 1
            $redis.sadd('vmpooler__discovered__' + pool['name'], vm['name'])

            $logger.log('s', "[?] [#{pool['name']}] '#{vm['name']}' added to 'discovered' queue")
          end

          inventory[vm['name']] = 1
        end
      rescue => err
        $logger.log('s', "[!] [#{pool['name']}] _check_pool failed with an error while running create_inventory: #{err}")
        raise(err)
      end
      inventory
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
      inventory = create_inventory(pool, provider)

      # RUNNING
      $redis.smembers("vmpooler__running__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            vm_lifetime = $redis.hget('vmpooler__vm__' + vm, 'lifetime') || $config[:config]['vm_lifetime'] || 12
            pool_check_response[:checked_running_vms] += 1
            check_running_vm(vm, pool['name'], vm_lifetime, provider)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool with an error while evaluating running VMs: #{err}")
          end
        else
          move_vm_queue(pool['name'], vm, 'running', 'completed', 'is a running VM but is missing from inventory.  Marking as completed.')
        end
      end

      # READY
      $redis.smembers("vmpooler__ready__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            pool_check_response[:checked_ready_vms] += 1
            check_ready_vm(vm, pool['name'], pool['ready_ttl'] || 0, provider)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error while evaluating ready VMs: #{err}")
          end
        else
          move_vm_queue(pool['name'], vm, 'ready', 'completed', 'is a ready VM but is missing from inventory.  Marking as completed.')
        end
      end

      # PENDING
      $redis.smembers("vmpooler__pending__#{pool['name']}").each do |vm|
        pool_timeout = pool['timeout'] || $config[:config]['timeout'] || 15
        if inventory[vm]
          begin
            pool_check_response[:checked_pending_vms] += 1
            check_pending_vm(vm, pool['name'], pool_timeout, provider)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error while evaluating pending VMs: #{err}")
          end
        else
          fail_pending_vm(vm, pool['name'], pool_timeout, false)
        end
      end

      # COMPLETED
      $redis.smembers("vmpooler__completed__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            pool_check_response[:destroyed_vms] += 1
            destroy_vm(vm, pool['name'], provider)
          rescue => err
            $redis.srem("vmpooler__completed__#{pool['name']}", vm)
            $redis.hdel("vmpooler__active__#{pool['name']}", vm)
            $redis.del("vmpooler__vm__#{vm}")
            $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error while evaluating completed VMs: #{err}")
          end
        else
          $logger.log('s', "[!] [#{pool['name']}] '#{vm}' not found in inventory, removed from 'completed' queue")
          $redis.srem("vmpooler__completed__#{pool['name']}", vm)
          $redis.hdel("vmpooler__active__#{pool['name']}", vm)
          $redis.del("vmpooler__vm__#{vm}")
        end
      end

      # DISCOVERED
      begin
        $redis.smembers("vmpooler__discovered__#{pool['name']}").each do |vm|
          %w[pending ready running completed].each do |queue|
            if $redis.sismember("vmpooler__#{queue}__#{pool['name']}", vm)
              $logger.log('d', "[!] [#{pool['name']}] '#{vm}' found in '#{queue}', removed from 'discovered' queue")
              $redis.srem("vmpooler__discovered__#{pool['name']}", vm)
            end
          end

          if $redis.sismember("vmpooler__discovered__#{pool['name']}", vm)
            $redis.smove("vmpooler__discovered__#{pool['name']}", "vmpooler__completed__#{pool['name']}", vm)
          end
        end
      rescue => err
        $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error while evaluating discovered VMs: #{err}")
      end

      # MIGRATIONS
      $redis.smembers("vmpooler__migrating__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            pool_check_response[:migrated_vms] += 1
            migrate_vm(vm, pool['name'], provider)
          rescue => err
            $logger.log('s', "[x] [#{pool['name']}] '#{vm}' failed to migrate: #{err}")
          end
        end
      end

      # UPDATE TEMPLATE
      # Evaluates a pool template to ensure templates are prepared adequately for the configured provider
      # If a pool template configuration change is detected then template preparation is repeated for the new template
      # Additionally, a pool will drain ready and pending instances
      evaluate_template(pool, provider)

      # REPOPULATE
      # Do not attempt to repopulate a pool while a template is updating
      unless pool_mutex(pool['name']).locked?
        ready = $redis.scard("vmpooler__ready__#{pool['name']}")
        total = $redis.scard("vmpooler__pending__#{pool['name']}") + ready

        $metrics.gauge("ready.#{pool['name']}", $redis.scard("vmpooler__ready__#{pool['name']}"))
        $metrics.gauge("running.#{pool['name']}", $redis.scard("vmpooler__running__#{pool['name']}"))

        if $redis.get("vmpooler__empty__#{pool['name']}")
          $redis.del("vmpooler__empty__#{pool['name']}") unless ready.zero?
        elsif ready.zero?
          $redis.set("vmpooler__empty__#{pool['name']}", 'true')
          $logger.log('s', "[!] [#{pool['name']}] is empty")
        end

        # Check to see if a pool size change has been made via the configuration API
        # Since check_pool runs in a loop it does not
        # otherwise identify this change when running
        update_pool_size(pool)

        if total < pool['size']
          (1..(pool['size'] - total)).each do |_i|
            if $redis.get('vmpooler__tasks__clone').to_i < $config[:config]['task_limit'].to_i
              begin
                $redis.incr('vmpooler__tasks__clone')
                pool_check_response[:cloned_vms] += 1
                clone_vm(pool, provider)
              rescue => err
                $logger.log('s', "[!] [#{pool['name']}] clone failed during check_pool with an error: #{err}")
                $redis.decr('vmpooler__tasks__clone')
                raise
              end
            end
          end
        end
      end

      # Remove VMs in excess of the configured pool size
      remove_excess_vms(pool, provider, ready, total)

      pool_check_response
    end

    # Create a provider object, usually based on the providers/*.rb class, that implements providers/base.rb
    # provider_class: Needs to match a class in the Vmpooler::PoolManager::Provider namespace. This is
    #                 either as a gem in the LOADPATH or in providers/*.rb ie Vmpooler::PoolManager::Provider::X
    # provider_name:  Should be a unique provider name
    #
    # returns an object Vmpooler::PoolManager::Provider::*
    # or raises an error if the class does not exist
    def create_provider_object(config, logger, metrics, provider_class, provider_name, options)
      provider_klass = Vmpooler::PoolManager::Provider
      provider_klass.constants.each do |classname|
        next unless classname.to_s.casecmp(provider_class) == 0
        return provider_klass.const_get(classname).new(config, logger, metrics, provider_name, options)
      end
      raise("Provider '#{provider_class}' is unknown for pool with provider name '#{provider_name}'") if provider.nil?
    end

    def execute!(maxloop = 0, loop_delay = 1)
      $logger.log('d', 'starting vmpooler')

      # Clear out the tasks manager, as we don't know about any tasks at this point
      $redis.set('vmpooler__tasks__clone', 0)
      # Clear out vmpooler__migrations since stale entries may be left after a restart
      $redis.del('vmpooler__migration')
      # Ensure template deltas are created on each startup
      $redis.del('vmpooler__template__prepared')

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
          $providers[provider_name] = create_provider_object($config, $logger, $metrics, provider_class, provider_name, {}) if $providers[provider_name].nil?
        rescue => err
          $logger.log('s', "Error while creating provider for pool #{pool['name']}: #{err}")
          raise
        end
      end

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

        sleep(loop_delay)

        unless maxloop.zero?
          break if loop_count >= maxloop
          loop_count += 1
        end
      end
    end
  end
end
