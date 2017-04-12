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
        _check_pending_vm(vm, pool, timeout, provider)
      end
    end

    def slots_available?(slots, max_slots)
      # Returns slots in use unless max is reached
      return slots unless slots >= max_slots
    end

    def open_socket(host, domain=nil, timeout=5, port=22, &block)
      Timeout.timeout(timeout) do
        target_host = host
        target_host = "#{host}.#{domain}" if domain
        sock = TCPSocket.new target_host, port
        begin
          yield sock if block_given?
        ensure
          sock.close
        end
      end
    end

    def _check_pending_vm(vm, pool, timeout, provider)
      host = provider.find_vm(vm)

      if ! host
        fail_pending_vm(vm, pool, timeout, false)
        return
      end
      open_socket vm
      move_pending_vm_to_ready(vm, pool, host)
    rescue
      fail_pending_vm(vm, pool, timeout)
    end

    def remove_nonexistent_vm(vm, pool)
      $redis.srem("vmpooler__pending__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")
    end

    def fail_pending_vm(vm, pool, timeout, exists=true)
      clone_stamp = $redis.hget("vmpooler__vm__#{vm}", 'clone')
      return if ! clone_stamp

      time_since_clone = (Time.now - Time.parse(clone_stamp)) / 60
      if time_since_clone > timeout
        if exists
          $redis.smove('vmpooler__pending__' + pool, 'vmpooler__completed__' + pool, vm)
          $logger.log('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
        else
          remove_nonexistent_vm(vm, pool)
        end
      end
    rescue => err
      $logger.log('d', "Fail pending VM failed with an error: #{err}")
    end

    def move_pending_vm_to_ready(vm, pool, host)
      if (host.summary) &&
          (host.summary.guest) &&
          (host.summary.guest.hostName) &&
          (host.summary.guest.hostName == vm)

        begin
          Socket.getaddrinfo(vm, nil)  # WTF?
        rescue
        end

        clone_time = $redis.hget('vmpooler__vm__' + vm, 'clone')
        finish = '%.2f' % (Time.now - Time.parse(clone_time)) if clone_time

        $redis.smove('vmpooler__pending__' + pool, 'vmpooler__ready__' + pool, vm)
        $redis.hset('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm, finish)

        $logger.log('s', "[>] [#{pool}] '#{vm}' moved to 'ready' queue")
      end
    end

    def check_ready_vm(vm, pool, ttl, provider)
      Thread.new do
        if ttl > 0
          if (((Time.now - host.runtime.bootTime) / 60).to_s[/^\d+\.\d{1}/].to_f) > ttl
            $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

            $logger.log('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
            return
          end
        end

        check_stamp = $redis.hget('vmpooler__vm__' + vm, 'check')

        if
          (!check_stamp) ||
          (((Time.now - Time.parse(check_stamp)) / 60) > $config[:config]['vm_checktime'])

          $redis.hset('vmpooler__vm__' + vm, 'check', Time.now)

          host = provider.find_vm(vm)

          if host
            if
              (host.runtime) &&
              (host.runtime.powerState) &&
              (host.runtime.powerState != 'poweredOn')

              $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

              $logger.log('d', "[!] [#{pool}] '#{vm}' appears to be powered off, removed from 'ready' queue")
              return
            end

            if
              (host.summary.guest) &&
              (host.summary.guest.hostName) &&
              (host.summary.guest.hostName != vm)

              $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

              $logger.log('d', "[!] [#{pool}] '#{vm}' has mismatched hostname, removed from 'ready' queue")
              return
            end
          else
            $redis.srem('vmpooler__ready__' + pool, vm)

            $logger.log('s', "[!] [#{pool}] '#{vm}' not found in vCenter inventory, removed from 'ready' queue")
          end

          begin
            open_socket vm
          rescue
            if $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
              $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")
            else
              $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, and failed to remove from 'ready' queue")
            end
            return
          end
        end
      end
    end

    def check_running_vm(vm, pool, ttl, provider)
      Thread.new do
        _check_running_vm(vm, pool, ttl, provider)
      end
    end

    def _check_running_vm(vm, pool, ttl, provider)
      host = provider.find_vm(vm)

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
      template = pool['template']
      folder = pool['folder']
      datastore = pool['datastore']
      target = pool['clone_target']
      vm = {}

      if template =~ /\//
        templatefolders = template.split('/')
        vm['template'] = templatefolders.pop
      end

      if templatefolders
        vm[vm['template']] = provider.find_folder(templatefolders.join('/')).find(vm['template'])
      else
        fail 'Please provide a full path to the template'
      end

      if vm['template'].length == 0
        fail "Unable to find template '#{vm['template']}'!"
      end

      # Generate a randomized hostname
      o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
      vm['hostname'] = $config[:config]['prefix'] + o[rand(25)] + (0...14).map { o[rand(o.length)] }.join

      # Add VM to Redis inventory ('pending' pool)
      $redis.sadd('vmpooler__pending__' + vm['template'], vm['hostname'])
      $redis.hset('vmpooler__vm__' + vm['hostname'], 'clone', Time.now)
      $redis.hset('vmpooler__vm__' + vm['hostname'], 'template', vm['template'])

      # Annotate with creation time, origin template, etc.
      # Add extraconfig options that can be queried by vmtools
      configSpec = RbVmomi::VIM.VirtualMachineConfigSpec(
        annotation: JSON.pretty_generate(
            name: vm['hostname'],
            created_by: $config[:vsphere]['username'],
            base_template: vm['template'],
            creation_timestamp: Time.now.utc
        ),
        extraConfig: [
            { key: 'guestinfo.hostname',
              value: vm['hostname']
            }
        ]
      )

      # Choose a clone target
      if target
        $clone_target = provider.find_least_used_host(target)
      elsif $config[:config]['clone_target']
        $clone_target = provider.find_least_used_host($config[:config]['clone_target'])
      end

      # Put the VM in the specified folder and resource pool
      relocateSpec = RbVmomi::VIM.VirtualMachineRelocateSpec(
        datastore: provider.find_datastore(datastore),
        host: $clone_target,
        diskMoveType: :moveChildMostDiskBacking
      )

      # Create a clone spec
      spec = RbVmomi::VIM.VirtualMachineCloneSpec(
        location: relocateSpec,
        config: configSpec,
        powerOn: true,
        template: false
      )

      # Clone the VM
      $logger.log('d', "[ ] [#{vm['template']}] '#{vm['hostname']}' is being cloned from '#{vm['template']}'")

      begin
        start = Time.now
        vm[vm['template']].CloneVM_Task(
          folder: provider.find_folder(folder),
          name: vm['hostname'],
          spec: spec
        ).wait_for_completion
        finish = '%.2f' % (Time.now - start)

        $redis.hset('vmpooler__clone__' + Date.today.to_s, vm['template'] + ':' + vm['hostname'], finish)
        $redis.hset('vmpooler__vm__' + vm['hostname'], 'clone_time', finish)

        $logger.log('s', "[+] [#{vm['template']}] '#{vm['hostname']}' cloned from '#{vm['template']}' in #{finish} seconds")
      rescue => err
        $logger.log('s', "[!] [#{vm['template']}] '#{vm['hostname']}' clone failed with an error: #{err}")
        $redis.srem('vmpooler__pending__' + vm['template'], vm['hostname'])
        raise
      end

      $redis.decr('vmpooler__tasks__clone')

      $metrics.timing("clone.#{vm['template']}", finish)
    end

    # Destroy a VM
    def destroy_vm(vm, pool, provider)
      Thread.new do
        $redis.srem('vmpooler__completed__' + pool, vm)
        $redis.hdel('vmpooler__active__' + pool, vm)
        $redis.hset('vmpooler__vm__' + vm, 'destroy', Time.now)

        # Auto-expire metadata key
        $redis.expire('vmpooler__vm__' + vm, ($config[:redis]['data_ttl'].to_i * 60 * 60))

        host = provider.find_vm(vm)

        if host
          start = Time.now

          if
            (host.runtime) &&
            (host.runtime.powerState) &&
            (host.runtime.powerState == 'poweredOn')

            $logger.log('d', "[ ] [#{pool}] '#{vm}' is being shut down")
            host.PowerOffVM_Task.wait_for_completion
          end

          host.Destroy_Task.wait_for_completion
          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[-] [#{pool}] '#{vm}' destroyed in #{finish} seconds")
          $metrics.timing("destroy.#{pool}", finish)
        end
      end
    end

    def create_vm_disk(vm, disk_size, provider)
      Thread.new do
        _create_vm_disk(vm, disk_size, provider)
      end
    end

    def _create_vm_disk(vm, disk_size, provider)
      host = provider.find_vm(vm)

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
          provider.add_disk(host, disk_size, datastore)

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

    def create_vm_snapshot(vm, snapshot_name, provider)
      Thread.new do
        _create_vm_snapshot(vm, snapshot_name, provider)
      end
    end

    def _create_vm_snapshot(vm, snapshot_name, provider)
      host = provider.find_vm(vm)

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

    def revert_vm_snapshot(vm, snapshot_name, provider)
      Thread.new do
        _revert_vm_snapshot(vm, snapshot_name, provider)
      end
    end

    def _revert_vm_snapshot(vm, snapshot_name, provider)
      host = provider.find_vm(vm)

      if host
        snapshot = provider.find_snapshot(host, snapshot_name)

        if snapshot
          $logger.log('s', "[ ] [snapshot_manager] '#{vm}' is being reverted to snapshot '#{snapshot_name}'")

          start = Time.now

          snapshot.RevertToSnapshot_Task.wait_for_completion

          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[<] [snapshot_manager] '#{vm}' reverted to snapshot in #{finish} seconds")
        end
      end
    end

    def check_disk_queue(maxloop = 0, loop_delay = 5)
      $logger.log('d', "[*] [disk_manager] starting worker thread")

      $providers['disk_manager'] ||= Vmpooler::VsphereHelper.new $config, $metrics
      $threads['disk_manager'] = Thread.new do
        loop_count = 1
        loop do
          _check_disk_queue $providers['disk_manager']
          sleep(loop_delay)

          unless maxloop.zero?
            break if loop_count >= maxloop
            loop_count += 1
          end
        end
      end
    end

    def _check_disk_queue(provider)
      vm = $redis.spop('vmpooler__tasks__disk')

      unless vm.nil?
        begin
          vm_name, disk_size = vm.split(':')
          create_vm_disk(vm_name, disk_size, provider)
        rescue
          $logger.log('s', "[!] [disk_manager] disk creation appears to have failed")
        end
      end
    end

    def check_snapshot_queue(maxloop = 0, loop_delay = 5)
      $logger.log('d', "[*] [snapshot_manager] starting worker thread")

      $providers['snapshot_manager'] ||= Vmpooler::VsphereHelper.new $config, $metrics

      $threads['snapshot_manager'] = Thread.new do
        loop_count = 1
        loop do
          _check_snapshot_queue $providers['snapshot_manager']
          sleep(loop_delay)

          unless maxloop.zero?
            break if loop_count >= maxloop
            loop_count += 1
          end
        end
      end
    end

    def _check_snapshot_queue(provider)
      vm = $redis.spop('vmpooler__tasks__snapshot')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          create_vm_snapshot(vm_name, snapshot_name, provider)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot appears to have failed")
        end
      end

      vm = $redis.spop('vmpooler__tasks__snapshot-revert')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          revert_vm_snapshot(vm_name, snapshot_name, provider)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot revert appears to have failed")
        end
      end
    end

    def migration_limit(migration_limit)
      # Returns migration_limit setting when enabled
      return false if migration_limit == 0 || ! migration_limit
      migration_limit if migration_limit >= 1
    end

    def migrate_vm(vm, pool, provider)
      Thread.new do
        _migrate_vm(vm, pool, provider)
      end
    end

    def _migrate_vm(vm, pool, provider)
      begin
        $redis.srem('vmpooler__migrating__' + pool, vm)
        vm_object = provider.find_vm(vm)
        parent_host, parent_host_name = get_vm_host_info(vm_object)
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
            host, host_name = provider.find_least_used_compatible_host(vm_object)
            if host == parent_host
              $logger.log('s', "[ ] [#{pool}] No migration required for '#{vm}' running on #{parent_host_name}")
            else
              finish = migrate_vm_and_record_timing(vm_object, vm, pool, host, parent_host_name, host_name, provider)
              $logger.log('s', "[>] [#{pool}] '#{vm}' migrated from #{parent_host_name} to #{host_name} in #{finish} seconds")
            end
            remove_vmpooler_migration_vm(pool, vm)
          end
        end
      rescue => err
        $logger.log('s', "[x] [#{pool}] '#{vm}' migration failed with an error: #{err}")
        remove_vmpooler_migration_vm(pool, vm)
      end
    end

    def get_vm_host_info(vm_object)
      parent_host = vm_object.summary.runtime.host
      [parent_host, parent_host.name]
    end

    def remove_vmpooler_migration_vm(pool, vm)
      begin
        $redis.srem('vmpooler__migration', vm)
      rescue => err
        $logger.log('s', "[x] [#{pool}] '#{vm}' removal from vmpooler__migration failed with an error: #{err}")
      end
    end

    def migrate_vm_and_record_timing(vm_object, vm_name, pool, host, source_host_name, dest_host_name, provider)
      start = Time.now
      provider.migrate_vm_host(vm_object, host)
      finish = '%.2f' % (Time.now - start)
      $metrics.timing("migrate.#{pool}", finish)
      $metrics.increment("migrate_from.#{source_host_name}")
      $metrics.increment("migrate_to.#{dest_host_name}")
      checkout_to_migration = '%.2f' % (Time.now - Time.parse($redis.hget("vmpooler__vm__#{vm_name}", 'checkout')))
      $redis.hset("vmpooler__vm__#{vm_name}", 'migration_time', finish)
      $redis.hset("vmpooler__vm__#{vm_name}", 'checkout_to_migration', checkout_to_migration)
      finish
    end

    def evaluate_pool(pool, slots, maxloop = 0, loop_delay = 1)
      return if $redis.hget("vmpooler__pool__#{pool['name']}", 'slot')
      checking_pools = $redis.smembers('vmpooler__check__pool__pending')
      return if checking_pools.include? pool['name']
      $redis.sadd('vmpooler__check__pool__pending', pool['name'])
      loop_count = 1
      while (slots_available?($redis.smembers('vmpooler__check__pool').count, slots.to_i).nil?)
        sleep(loop_delay * 3)
        unless maxloop.zero?
          return if loop_count >= maxloop
          loop_count += 1
        end
      end
      slots_free = slots_available?($redis.smembers('vmpooler__check__pool').count, slots)
      next_slot = (slots_free.to_i + 1).to_s
      check_pool(pool, next_slot)
    rescue => err
      $logger.log('d', "[!] [#{pool['name']}] evaluating failed with an error: #{err}")
    end

    def check_pool(pool, slot)
      $redis.sadd('vmpooler__check__pool', pool['name'])
      $redis.srem('vmpooler__check__pool__pending', pool['name'])
      $redis.hset("vmpooler__pool__#{pool['name']}", 'slot', slot)

      $providers[slot] ||= Vmpooler::VsphereHelper.new $config, $metrics

      $threads[slot] = Thread.new do
        _check_pool(pool, $providers[slot])
      end
    rescue => err
      $logger.log('d', "[!] [#{pool['name']}] checking failed with an error: #{err}")
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
      $redis.srem('vmpooler__check__pool', pool['name'])
      $redis.hdel("vmpooler__pool__#{pool['name']}", 'slot')
    rescue => err
      $logger.log('d', "[!] [#{pool['name']}] _check_pool failed with an error: #{err}")
      $redis.srem('vmpooler__check__pool', pool['name'])
      $redis.hdel("vmpooler__pool__#{pool['name']}", 'slot')
      raise
    end

    def clean_stale_redis_queues
      # Clear out the tasks manager, as we don't know about any tasks at this point
      $redis.set('vmpooler__tasks__clone', 0)
      # Clear out vmpooler__migrations since stale entries may be left after a restart
      $redis.del('vmpooler__migration')
      # Clear out pool entries used to track slot usage
      to_clear = $redis.smembers('vmpooler__check__pool')
      to_clear.each do |pool_name|
        $redis.del("vmpooler__pool__#{pool_name}")
      end
      # Clear out vmpooler__check__pool entries to ensure starting with a clean state
      $redis.del('vmpooler__check__pool')
      $redis.del('vmpooler__check__pool__pending')
    end

    def execute!(maxloop = 0, loop_delay = 1)
      $logger.log('d', 'starting vmpooler')

      clean_stale_redis_queues

      task_limit = $config[:config]['task_limit']

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
          evaluate_pool(pool, task_limit, maxloop, loop_delay)
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
