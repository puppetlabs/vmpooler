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

      # per pool VM Backing Services
      $backing_services = {}

      # Our thread-tracker object
      $threads = {}

      # WARNING DEBUG
      #$logger.log('d',"Flushing REDIS  WARNING!!!")
      #$redis.flushdb
    end

    # Check the state of a VM
    # DONE
    def check_pending_vm(vm, pool, timeout, backingservice)
      Thread.new do
        begin
          _check_pending_vm(vm, pool, timeout, backingservice)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' errored while checking a pending vm : #{err}")
          fail_pending_vm(vm, pool, timeout)
          raise
        end
      end
    end

    # DONE
    def _check_pending_vm(vm, pool, timeout, backingservice)
      host = backingservice.get_vm(vm)
      if ! host
        fail_pending_vm(vm, pool, timeout, false)
        return
      end
      if backingservice.is_vm_ready?(vm,pool,timeout)
        move_pending_vm_to_ready(vm, pool, host)
      else
        fail "VM is not ready"
      end
    end

    # DONE
    def remove_nonexistent_vm(vm, pool)
      $redis.srem("vmpooler__pending__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    # DONE
    def fail_pending_vm(vm, pool, timeout, exists=true)
      clone_stamp = $redis.hget("vmpooler__vm__#{vm}", 'clone')
      return true if ! clone_stamp

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

    # DONE
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

    # DONE
    def check_ready_vm(vm, pool, ttl, backingservice)
      Thread.new do
        begin
          _check_ready_vm(vm, pool, ttl, backingservice)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' failed while checking a ready vm : #{err}")
          raise
        end
      end
    end

    # DONE
    def _check_ready_vm(vm, pool, ttl, backingservice)
      host = backingservice.get_vm(vm)
      # Check if the host even exists
      if !host
        $redis.srem('vmpooler__ready__' + pool, vm)
        $logger.log('s', "[!] [#{pool}] '#{vm}' not found in inventory for pool #{pool}, removed from 'ready' queue")
        return
      end

      # Check if the hosts TTL has expired
      if ttl > 0
        if (((Time.now - host['boottime']) / 60).to_s[/^\d+\.\d{1}/].to_f) > ttl
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

          $logger.log('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
        end
      end

      # Periodically check that the VM is available
      check_stamp = $redis.hget('vmpooler__vm__' + vm, 'check')
      if
        (!check_stamp) ||
        (((Time.now - Time.parse(check_stamp)) / 60) > $config[:config]['vm_checktime'])

        $redis.hset('vmpooler__vm__' + vm, 'check', Time.now)

        # Check if the VM is not powered on
        if
          (host['powerstate'] != 'PoweredOn')
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' appears to be powered off, removed from 'ready' queue")
        end

        # Check if the hostname has magically changed from underneath Pooler
        if (host['hostname'] != vm)
          $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' has mismatched hostname, removed from 'ready' queue")
        end

        # Check if the VM is still ready/available
        begin
          fail "VM #{vm} is not ready" unless backingservice.is_vm_ready?(vm,pool,5)
        rescue
          if $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
            $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")
          else
            $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, and failed to remove from 'ready' queue")
          end
        end
      end
    end

    # DONE
    def check_running_vm(vm, pool, ttl, backingservice)
      Thread.new do
        begin
          _check_running_vm(vm, pool, ttl, backingservice)
        rescue => err
          $logger.log('s', "[!] [#{pool}] '#{vm}' failed while checking VM with an error: #{err}")
          raise
        end
      end
    end

    # DONE
    def _check_running_vm(vm, pool, ttl, backingservice)
      host = backingservice.get_vm(vm)

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

    # DONE
    def move_vm_queue(pool, vm, queue_from, queue_to, msg)
      $redis.smove("vmpooler__#{queue_from}__#{pool}", "vmpooler__#{queue_to}__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' #{msg}")
    end

    # DONE
    def clone_vm(pool, backingservice)
      Thread.new do
        begin
          pool_name = pool['name']

          # Generate a randomized hostname
          o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
          new_vmname = $config[:config]['prefix'] + o[rand(25)] + (0...14).map { o[rand(o.length)] }.join

          # Add VM to Redis inventory ('pending' pool)
          $redis.sadd('vmpooler__pending__' + pool_name, new_vmname)
          $redis.hset('vmpooler__vm__' + new_vmname, 'clone', Time.now)
          $redis.hset('vmpooler__vm__' + new_vmname, 'template', pool_name)

          begin
            start = Time.now
            backingservice.create_vm(pool,new_vmname)
            finish = '%.2f' % (Time.now - start)

            $redis.hset('vmpooler__clone__' + Date.today.to_s, pool_name + ':' + new_vmname, finish)
            $redis.hset('vmpooler__vm__' + new_vmname, 'clone_time', finish)
            $logger.log('s', "[+] [#{pool_name}] '#{new_vmname}' cloned from '#{pool_name}' in #{finish} seconds")

            $metrics.timing("clone.#{pool_name}", finish)
          rescue => err
            $logger.log('s', "[!] [#{pool_name}] '#{new_vmname}' clone failed with an error: #{err}")
            $redis.srem('vmpooler__pending__' + pool_name, new_vmname)
            raise
          ensure
            $redis.decr('vmpooler__tasks__clone')
          end
        rescue => err
          $logger.log('s', "[!] [#{pool['name']}] failed while preparing to clone with an error: #{err}")
          raise
        end
      end
    end

    # Destroy a VM
    # DONE
    def destroy_vm(vm, pool, backingservice)
      Thread.new do
        begin
          _destroy_vm(vm, pool, backingservice)
        rescue => err
          $logger.log('d', "[!] [#{pool}] '#{vm}' failed while destroying the VM with an error: #{err}")
          raise
        end
      end
    end

    # Destroy a VM
    # DONE
    def _destroy_vm(vm, pool, backingservice)
      $redis.srem('vmpooler__completed__' + pool, vm)
      $redis.hdel('vmpooler__active__' + pool, vm)
      $redis.hset('vmpooler__vm__' + vm, 'destroy', Time.now)

      # Auto-expire metadata key
      $redis.expire('vmpooler__vm__' + vm, ($config[:redis]['data_ttl'].to_i * 60 * 60))

      start = Time.now

      backingservice.destroy_vm(vm,pool)

      finish = '%.2f' % (Time.now - start)
      $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
      $metrics.timing("destroy.#{pool}", finish)
    end

    def create_vm_disk(vm, disk_size, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      Thread.new do
        _create_vm_disk(vm, disk_size, vsphere)
      end
    end

    def _create_vm_disk(vm, disk_size, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      host = vsphere.find_vm(vm)

      if (host) && ((! disk_size.nil?) && (! disk_size.empty?) && (disk_size.to_i > 0))
        $logger.log('s', "[ ] [disk_manager] '#{vm}' is attaching a #{disk_size}gb disk")

        start = Time.now

        template = $redis.hget('vmpooler__vm__' + vm, 'template')
        datastore = nil

        $config[:pools].each do |pool|
          if pool['name'] == template
            datastore = pool['datastore']
          end
        end

        if ((! datastore.nil?) && (! datastore.empty?))
          vsphere.add_disk(host, disk_size, datastore)

          rdisks = $redis.hget('vmpooler__vm__' + vm, 'disk')
          disks = rdisks ? rdisks.split(':') : []
          disks.push("+#{disk_size}gb")
          $redis.hset('vmpooler__vm__' + vm, 'disk', disks.join(':'))

          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[+] [disk_manager] '#{vm}' attached #{disk_size}gb disk in #{finish} seconds")
        else
          $logger.log('s', "[+] [disk_manager] '#{vm}' failed to attach disk")
        end
      end
    end

    def create_vm_snapshot(vm, snapshot_name, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      Thread.new do
        _create_vm_snapshot(vm, snapshot_name, vsphere)
      end
    end

    def _create_vm_snapshot(vm, snapshot_name, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      host = vsphere.find_vm(vm)

      if (host) && ((! snapshot_name.nil?) && (! snapshot_name.empty?))
        $logger.log('s', "[ ] [snapshot_manager] '#{vm}' is being snapshotted")

        start = Time.now

        host.CreateSnapshot_Task(
          name: snapshot_name,
          description: 'vmpooler',
          memory: true,
          quiesce: true
        ).wait_for_completion

        finish = '%.2f' % (Time.now - start)

        $redis.hset('vmpooler__vm__' + vm, 'snapshot:' + snapshot_name, Time.now.to_s)

        $logger.log('s', "[+] [snapshot_manager] '#{vm}' snapshot created in #{finish} seconds")
      end
    end

    def revert_vm_snapshot(vm, snapshot_name, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      Thread.new do
        _revert_vm_snapshot(vm, snapshot_name, vsphere)
      end
    end

    def _revert_vm_snapshot(vm, snapshot_name, vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      host = vsphere.find_vm(vm)

      if host
        snapshot = vsphere.find_snapshot(host, snapshot_name)

        if snapshot
          $logger.log('s', "[ ] [snapshot_manager] '#{vm}' is being reverted to snapshot '#{snapshot_name}'")

          start = Time.now

          snapshot.RevertToSnapshot_Task.wait_for_completion

          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[<] [snapshot_manager] '#{vm}' reverted to snapshot in #{finish} seconds")
        end
      end
    end

    def check_disk_queue
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      $logger.log('d', "[*] [disk_manager] starting worker thread")

      $vsphere['disk_manager'] ||= Vmpooler::VsphereHelper.new $config, $metrics

      $threads['disk_manager'] = Thread.new do
        loop do
          _check_disk_queue $vsphere['disk_manager']
          sleep(5)
        end
      end
    end

    def _check_disk_queue(vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      vm = $redis.spop('vmpooler__tasks__disk')

      unless vm.nil?
        begin
          vm_name, disk_size = vm.split(':')
          create_vm_disk(vm_name, disk_size, vsphere)
        rescue
          $logger.log('s', "[!] [disk_manager] disk creation appears to have failed")
        end
      end
    end

    def check_snapshot_queue
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      $logger.log('d', "[*] [snapshot_manager] starting worker thread")

      $vsphere['snapshot_manager'] ||= Vmpooler::VsphereHelper.new $config, $metrics

      $threads['snapshot_manager'] = Thread.new do
        loop do
          _check_snapshot_queue $vsphere['snapshot_manager']
          sleep(5)
        end
      end
    end

    def _check_snapshot_queue(vsphere)
fail "NOT YET REFACTORED"      
# TODO This is all vSphere specific
      vm = $redis.spop('vmpooler__tasks__snapshot')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          create_vm_snapshot(vm_name, snapshot_name, vsphere)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot appears to have failed")
        end
      end

      vm = $redis.spop('vmpooler__tasks__snapshot-revert')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          revert_vm_snapshot(vm_name, snapshot_name, vsphere)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot revert appears to have failed")
        end
      end
    end

    # DONE
    def migration_limit(migration_limit)
      # Returns migration_limit setting when enabled
      return false if migration_limit == 0 || ! migration_limit
      migration_limit if migration_limit >= 1
    end

    # DONE
    def migrate_vm(vm, pool, backingservice)
      Thread.new do
        begin
          _migrate_vm(vm, pool, backingservice)
        rescue => err
          $logger.log('s', "[x] [#{pool}] '#{vm}' migration failed with an error: #{err}")
          remove_vmpooler_migration_vm(pool, vm)
        end
      end
    end

    # DONE
    def _migrate_vm(vm, pool, backingservice)
      $redis.srem('vmpooler__migrating__' + pool, vm)

      parent_host_name = backingservice.get_vm_host(vm)
      migration_limit = migration_limit $config[:config]['migration_limit']
      migration_count = $redis.scard('vmpooler__migration')

      if ! migration_limit
        $logger.log('s', "[ ] [#{pool}] '#{vm}' is running on #{parent_host_name}")
        return
      else
        if migration_count >= migration_limit
          $logger.log('s', "[ ] [#{pool}] '#{vm}' is running on #{parent_host_name}. No migration will be evaluated since the migration_limit has been reached")
          return
        else
          $redis.sadd('vmpooler__migration', vm)
          host_name = backingservice.find_least_used_compatible_host(vm)
          if host_name == parent_host_name
            $logger.log('s', "[ ] [#{pool}] No migration required for '#{vm}' running on #{parent_host_name}")
          else
            finish = migrate_vm_and_record_timing(vm, pool, parent_host_name, host_name, backingservice)
            $logger.log('s', "[>] [#{pool}] '#{vm}' migrated from #{parent_host_name} to #{host_name} in #{finish} seconds")
          end
          remove_vmpooler_migration_vm(pool, vm)
        end
      end
    end

    # DONE
    def remove_vmpooler_migration_vm(pool, vm)
      begin
        $redis.srem('vmpooler__migration', vm)
      rescue => err
        $logger.log('s', "[x] [#{pool}] '#{vm}' removal from vmpooler__migration failed with an error: #{err}")
      end
    end

    # DONE
    def migrate_vm_and_record_timing(vm_name, pool, source_host_name, dest_host_name, backingservice)
      start = Time.now
      backingservice.migrate_vm_to_host(vm_name, dest_host_name)
      finish = '%.2f' % (Time.now - start)
      $metrics.timing("migrate.#{pool}", finish)
      $metrics.increment("migrate_from.#{source_host_name}")
      $metrics.increment("migrate_to.#{dest_host_name}")
      checkout_to_migration = '%.2f' % (Time.now - Time.parse($redis.hget("vmpooler__vm__#{vm_name}", 'checkout')))
      $redis.hset("vmpooler__vm__#{vm_name}", 'migration_time', finish)
      $redis.hset("vmpooler__vm__#{vm_name}", 'checkout_to_migration', checkout_to_migration)
      finish
    end

    # DONE
    def check_pool(pool)
      $logger.log('d', "[*] [#{pool['name']}] starting worker thread")

      case pool['backingservice']
      when 'vsphere'
        # TODO what about the helper
        $backing_services[pool['name']] ||= Vmpooler::PoolManager::BackingService::Vsphere.new({ 'metrics' => $metrics}) # TODO Vmpooler::VsphereHelper.new $config[:vsphere], $metrics
      when 'dummy'
        $backing_services[pool['name']] ||= Vmpooler::PoolManager::BackingService::Dummy.new($config[:backingservice][:dummy])
      else
         $logger.log('s', "[!] backing service #{pool['backingservice']} is unknown for pool [#{pool['name']}]")
      end

      $threads[pool['name']] = Thread.new do
        loop do
          _check_pool(pool, $backing_services[pool['name']])
# TODO Should this be configurable?
          sleep(2) # Should be 5
        end
      end
    end

    def _check_pool(pool,backingservice)
      # INVENTORY
      inventory = {}
      begin
        backingservice.vms_in_pool(pool).each do |vm|
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
            check_running_vm(vm, pool['name'], vm_lifetime, backingservice)
          rescue => err
            $logger.log('d', "[!] [#{pool['name']}] _check_pool with an error while evaluating running VMs: #{err}")
          end
        end
      end

      # READY
      $redis.smembers("vmpooler__ready__#{pool['name']}").each do |vm|
        if inventory[vm]
          begin
            check_ready_vm(vm, pool['name'], pool['ready_ttl'] || 0, backingservice)
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
            check_pending_vm(vm, pool['name'], pool_timeout, backingservice)
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
            destroy_vm(vm, pool['name'], backingservice)
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
            migrate_vm(vm, pool['name'], backingservice)
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
              clone_vm(pool,backingservice)
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

    def execute!
      $logger.log('d', 'starting vmpooler')

      # Clear out the tasks manager, as we don't know about any tasks at this point
      $redis.set('vmpooler__tasks__clone', 0)
      # Clear out vmpooler__migrations since stale entries may be left after a restart
      $redis.del('vmpooler__migration')
      # Set default backingservice for all pools that do not have one defined
      $config[:pools].each do |pool|
        pool['backingservice'] = 'vsphere' if pool['backingservice'].nil?
      end

      loop do
        # DEBUG TO DO
        # if ! $threads['disk_manager']
        #   check_disk_queue
        # elsif ! $threads['disk_manager'].alive?
        #   $logger.log('d', "[!] [disk_manager] worker thread died, restarting")
        #   check_disk_queue
        # end

        # if ! $threads['snapshot_manager']
        #   check_snapshot_queue
        # elsif ! $threads['snapshot_manager'].alive?
        #   $logger.log('d', "[!] [snapshot_manager] worker thread died, restarting")
        #   check_snapshot_queue
        # end

        $config[:pools].each do |pool|
          if ! $threads[pool['name']]
            check_pool(pool)
          elsif ! $threads[pool['name']].alive?
            $logger.log('d', "[!] [#{pool['name']}] worker thread died, restarting")
            check_pool(pool)
          end
        end

        sleep(1)
      end
    end
  end
end
