module Vmpooler
  class PoolManager
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
    end

    # Check the state of a VM
    def check_pending_vm(vm, pool, timeout, provider)
      Thread.new do
        begin
          _check_pending_vm(vm, pool, timeout, provider)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' errored while checking a pending vm : #{err}")
          fail_pending_vm(vm, pool, timeout)
          raise
        end
      end
    end

    def _check_pending_vm(vm, pool, timeout, provider)
      host = provider.get_vm(pool, vm)
      if ! host
        fail_pending_vm(vm, pool, timeout, false)
        return
      end
      if provider.vm_ready?(pool, vm)
        move_pending_vm_to_ready(vm, pool, host)
      else
        fail_pending_vm(vm, pool, timeout)
      end
    end

    def remove_nonexistent_vm(vm, pool)
      $redis.srem("vmpooler__pending__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    def fail_pending_vm(vm, pool, timeout, exists = true)
      clone_stamp = $redis.hget("vmpooler__vm__#{vm}", 'clone')
      return true if !clone_stamp

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
          Socket.getaddrinfo(vm, nil)  # WTF? I assume this is just priming the local DNS resolver cache?!?!
        rescue
        end

        clone_time = $redis.hget('vmpooler__vm__' + vm, 'clone')
        finish = '%.2f' % (Time.now - Time.parse(clone_time)) if clone_time

        $redis.smove('vmpooler__pending__' + pool, 'vmpooler__ready__' + pool, vm)
        $redis.hset('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm, finish)

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
      check_stamp = $redis.hget('vmpooler__vm__' + vm, 'check')
      return if check_stamp && (((Time.now - Time.parse(check_stamp)) / 60) <= $config[:config]['vm_checktime'])

      host = provider.get_vm(pool, vm)
      # Check if the host even exists
      if !host
        $redis.srem('vmpooler__ready__' + pool, vm)
        $logger.log('s', "[!] [#{pool}] '#{vm}' not found in inventory, removed from 'ready' queue")
        return
      end

      # Check if the hosts TTL has expired
      if ttl > 0
        if (((Time.now - host['boottime']) / 60).to_s[/^\d+\.\d{1}/].to_f) > ttl
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

          $logger.log('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
          return
        end
      end

      $redis.hset('vmpooler__vm__' + vm, 'check', Time.now)
      # Check if the VM is not powered on
      unless (host['powerstate'].casecmp('poweredon') == 0)
        $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
        $logger.log('d', "[!] [#{pool}] '#{vm}' appears to be powered off, removed from 'ready' queue")
        return
      end

      # Check if the hostname has magically changed from underneath Pooler
      if (host['hostname'] != vm)
        $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
        $logger.log('d', "[!] [#{pool}] '#{vm}' has mismatched hostname, removed from 'ready' queue")
        return
      end

      # Check if the VM is still ready/available
      begin
        fail "VM #{vm} is not ready" unless provider.vm_ready?(pool, vm)
      rescue
        if $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")
        else
          $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, and failed to remove from 'ready' queue")
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
      host = provider.get_vm(pool, vm)

      if host
        queue_from, queue_to = 'running', 'completed'

        # Check that VM is within defined lifetime
        checkouttime = $redis.hget('vmpooler__active__' + pool, vm)
        if checkouttime
          running = (Time.now - Time.parse(checkouttime)) / 60 / 60

          if (ttl.to_i > 0) &&
              (running.to_i >= ttl.to_i)
            move_vm_queue(pool, vm, queue_from, queue_to, "reached end of TTL after #{ttl} hours")
          end
        end
      end
    end

    def move_vm_queue(pool, vm, queue_from, queue_to, msg)
      $redis.smove("vmpooler__#{queue_from}__#{pool}", "vmpooler__#{queue_to}__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' #{msg}")
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
        finish = '%.2f' % (Time.now - start)

        $redis.hset('vmpooler__clone__' + Date.today.to_s, pool_name + ':' + new_vmname, finish)
        $redis.hset('vmpooler__vm__' + new_vmname, 'clone_time', finish)
        $logger.log('s', "[+] [#{pool_name}] '#{new_vmname}' cloned in #{finish} seconds")

        $metrics.timing("clone.#{pool_name}", finish)
      rescue => err
        $logger.log('s', "[!] [#{pool_name}] '#{new_vmname}' clone failed with an error: #{err}")
        $redis.srem('vmpooler__pending__' + pool_name, new_vmname)
        raise
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
      $redis.srem('vmpooler__completed__' + pool, vm)
      $redis.hdel('vmpooler__active__' + pool, vm)
      $redis.hset('vmpooler__vm__' + vm, 'destroy', Time.now)

      # Auto-expire metadata key
      $redis.expire('vmpooler__vm__' + vm, ($config[:redis]['data_ttl'].to_i * 60 * 60))

      start = Time.now

      provider.destroy_vm(pool, vm)

      finish = '%.2f' % (Time.now - start)
      $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
      $metrics.timing("destroy.#{pool}", finish)
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
      raise("Invalid disk size of '#{disk_size}' passed") if (disk_size.nil?) || (disk_size.empty?) || (disk_size.to_i <= 0)

      $logger.log('s', "[ ] [disk_manager] '#{vm_name}' is attaching a #{disk_size}gb disk")

      start = Time.now

      result = provider.create_disk(pool_name, vm_name, disk_size.to_i)

      finish = '%.2f' % (Time.now - start)

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

      finish = '%.2f' % (Time.now - start)

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

      finish = '%.2f' % (Time.now - start)

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
      $logger.log('d', "[*] [disk_manager] starting worker thread")

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
      $logger.log('d', "[*] [snapshot_manager] starting worker thread")

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

    def migration_limit(migration_limit)
      # Returns migration_limit setting when enabled
      return false if migration_limit == 0 || ! migration_limit
      migration_limit if migration_limit >= 1
    end

    def migrate_vm(vm_name, pool_name, provider)
      Thread.new do
        begin
          _migrate_vm(vm_name, pool_name, provider)
        rescue => err
          $logger.log('s', "[x] [#{pool_name}] '#{vm_name}' migration failed with an error: #{err}")
          remove_vmpooler_migration_vm(pool_name, vm_name)
        end
      end
    end

    def _migrate_vm(vm_name, pool_name, provider)
      $redis.srem('vmpooler__migrating__' + pool_name, vm_name)

      parent_host_name = provider.get_vm_host(pool_name, vm_name)
      raise('Unable to determine which host the VM is running on') if parent_host_name.nil?
      migration_limit = migration_limit $config[:config]['migration_limit']
      migration_count = $redis.scard('vmpooler__migration')

      if ! migration_limit
        $logger.log('s', "[ ] [#{pool_name}] '#{vm_name}' is running on #{parent_host_name}")
        return
      else
        if migration_count >= migration_limit
          $logger.log('s', "[ ] [#{pool_name}] '#{vm_name}' is running on #{parent_host_name}. No migration will be evaluated since the migration_limit has been reached")
          return
        else
          $redis.sadd('vmpooler__migration', vm_name)
          host_name = provider.find_least_used_compatible_host(vm_name)
          if host_name == parent_host_name
            $logger.log('s', "[ ] [#{pool_name}] No migration required for '#{vm_name}' running on #{parent_host_name}")
          else
            finish = migrate_vm_and_record_timing(vm_name, pool_name, parent_host_name, host_name, provider)
            $logger.log('s', "[>] [#{pool_name}] '#{vm_name}' migrated from #{parent_host_name} to #{host_name} in #{finish} seconds")
          end
          remove_vmpooler_migration_vm(pool_name, vm_name)
        end
      end
    end

    def remove_vmpooler_migration_vm(pool, vm)
      begin
        $redis.srem('vmpooler__migration', vm)
      rescue => err
        $logger.log('s', "[x] [#{pool}] '#{vm}' removal from vmpooler__migration failed with an error: #{err}")
      end
    end

    def migrate_vm_and_record_timing(vm_name, pool_name, source_host_name, dest_host_name, provider)
      start = Time.now
      provider.migrate_vm_to_host(pool_name, vm_name, dest_host_name)
      finish = '%.2f' % (Time.now - start)
      $metrics.timing("migrate.#{pool_name}", finish)
      $metrics.increment("migrate_from.#{source_host_name}")
      $metrics.increment("migrate_to.#{dest_host_name}")
      checkout_to_migration = '%.2f' % (Time.now - Time.parse($redis.hget("vmpooler__vm__#{vm_name}", 'checkout')))
      $redis.hset("vmpooler__vm__#{vm_name}", 'migration_time', finish)
      $redis.hset("vmpooler__vm__#{vm_name}", 'checkout_to_migration', checkout_to_migration)
      finish
    end

    def check_pool(pool, maxloop = 0, loop_delay = 5)
      $logger.log('d', "[*] [#{pool['name']}] starting worker thread")

      $providers[pool['name']] ||= Vmpooler::VsphereHelper.new $config, $metrics

      $threads[pool['name']] = Thread.new do
        loop_count = 1
        loop do
          _check_pool(pool, $providers[pool['name']])
          sleep(loop_delay)

          unless maxloop.zero?
            break if loop_count >= maxloop
            loop_count += 1
          end
        end
      end
    end

    def _check_pool(pool, provider)
      # INVENTORY
      inventory = {}
      begin
        base = provider.find_folder(pool['folder'])

        base.childEntity.each do |vm|
          if
            (! $redis.sismember('vmpooler__running__' + pool['name'], vm['name'])) &&
            (! $redis.sismember('vmpooler__ready__' + pool['name'], vm['name'])) &&
            (! $redis.sismember('vmpooler__pending__' + pool['name'], vm['name'])) &&
            (! $redis.sismember('vmpooler__completed__' + pool['name'], vm['name'])) &&
            (! $redis.sismember('vmpooler__discovered__' + pool['name'], vm['name'])) &&
            (! $redis.sismember('vmpooler__migrating__' + pool['name'], vm['name']))

            $redis.sadd('vmpooler__discovered__' + pool['name'], vm['name'])

            $logger.log('s', "[?] [#{pool['name']}] '#{vm['name']}' added to 'discovered' queue")
          end

          inventory[vm['name']] = 1
        end
      rescue => err
        $logger.log('s', "[!] [#{pool['name']}] _check_pool failed with an error while inspecting inventory: #{err}")
      end

      # RUNNING
      $redis.smembers("vmpooler__running__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            vm_lifetime = $redis.hget('vmpooler__vm__' + vm, 'lifetime') || $config[:config]['vm_lifetime'] || 12
            check_running_vm(vm, pool['name'], vm_lifetime, provider)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool with an error while evaluating running VMs: #{err}")
          end
        end
      end

      # READY
      $redis.smembers("vmpooler__ready__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            check_ready_vm(vm, pool['name'], pool['ready_ttl'] || 0, provider)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error while evaluating ready VMs: #{err}")
          end
        end
      end

      # PENDING
      $redis.smembers("vmpooler__pending__#{pool['name']}").each do |vm|
        pool_timeout = pool['timeout'] || $config[:config]['timeout'] || 15
        if inventory[vm]
          begin
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
          %w(pending ready running completed).each do |queue|
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
            migrate_vm(vm, pool['name'], provider)
          rescue => err
            $logger.log('s', "[x] [#{pool['name']}] '#{vm}' failed to migrate: #{err}")
          end
        end
      end

      # REPOPULATE
      ready = $redis.scard("vmpooler__ready__#{pool['name']}")
      total = $redis.scard("vmpooler__pending__#{pool['name']}") + ready

      $metrics.gauge("ready.#{pool['name']}", $redis.scard("vmpooler__ready__#{pool['name']}"))
      $metrics.gauge("running.#{pool['name']}", $redis.scard("vmpooler__running__#{pool['name']}"))

      if $redis.get("vmpooler__empty__#{pool['name']}")
        unless ready == 0
          $redis.del("vmpooler__empty__#{pool['name']}")
        end
      else
        if ready == 0
          $redis.set("vmpooler__empty__#{pool['name']}", 'true')
          $logger.log('s', "[!] [#{pool['name']}] is empty")
        end
      end

      if total < pool['size']
        (1..(pool['size'] - total)).each do |_i|
          if $redis.get('vmpooler__tasks__clone').to_i < $config[:config]['task_limit'].to_i
            begin
              $redis.incr('vmpooler__tasks__clone')
              clone_vm(pool, provider)
            rescue => err
              $logger.log('s', "[!] [#{pool['name']}] clone failed during check_pool with an error: #{err}")
              $redis.decr('vmpooler__tasks__clone')
              raise
            end
          end
        end
      end
    rescue => err
      $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error: #{err}")
      raise
    end

    def execute!(maxloop = 0, loop_delay = 1)
      $logger.log('d', 'starting vmpooler')

      # Clear out the tasks manager, as we don't know about any tasks at this point
      $redis.set('vmpooler__tasks__clone', 0)
      # Clear out vmpooler__migrations since stale entries may be left after a restart
      $redis.del('vmpooler__migration')

      loop_count = 1
      loop do
        if ! $threads['disk_manager']
          check_disk_queue
        elsif ! $threads['disk_manager'].alive?
          $logger.log('d', "[!] [disk_manager] worker thread died, restarting")
          check_disk_queue
        end

        if ! $threads['snapshot_manager']
          check_snapshot_queue
        elsif ! $threads['snapshot_manager'].alive?
          $logger.log('d', "[!] [snapshot_manager] worker thread died, restarting")
          check_snapshot_queue
        end

        $config[:pools].each do |pool|
          if ! $threads[pool['name']]
            check_pool(pool)
          elsif ! $threads[pool['name']].alive?
            $logger.log('d', "[!] [#{pool['name']}] worker thread died, restarting")
            check_pool(pool)
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
