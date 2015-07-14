module Vmpooler
  class PoolManager
    def initialize(config, logger, redis, graphite=nil)
      $config = config

      # Load logger library
      $logger = logger

      unless graphite.nil?
        $graphite = graphite
      end

      # Connect to Redis
      $redis = redis

      # vSphere object
      $vsphere = {}

      # Our thread-tracker object
      $threads = {}
    end

    # Check the state of a VM
    def check_pending_vm(vm, pool, timeout)
      Thread.new do
        _check_pending_vm(vm, pool, timeout)
      end
    end

    def _check_pending_vm(vm, pool, timeout)
      host = $vsphere[pool].find_vm(vm)

      if host
        move_pending_vm_to_ready(vm, pool, host)
      else
        fail_pending_vm(vm, pool, timeout)
      end
    end

    def fail_pending_vm(vm, pool, timeout)
      clone_stamp = $redis.hget('vmpooler__vm__' + vm, 'clone')

      if (clone_stamp) &&
          (((Time.now - Time.parse(clone_stamp)) / 60) > timeout)

        $redis.smove('vmpooler__pending__' + pool, 'vmpooler__completed__' + pool, vm)

        $logger.log('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
      end
    end

    def move_pending_vm_to_ready(vm, pool, host)
      if (host.summary) &&
          (host.summary.guest) &&
          (host.summary.guest.hostName) &&
          (host.summary.guest.hostName == vm)

        begin
          Socket.getaddrinfo(vm, nil)
        rescue
        end

        clone_time = $redis.hget('vmpooler__vm__' + vm, 'clone')
        finish = '%.2f' % (Time.now - Time.parse(clone_time)) if clone_time

        $redis.smove('vmpooler__pending__' + pool, 'vmpooler__ready__' + pool, vm)
        $redis.hset('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm, finish)

        $logger.log('s', "[>] [#{pool}] '#{vm}' moved to 'ready' queue")
      end
    end

    def check_ready_vm(vm, pool, ttl)
      Thread.new do
        if ttl > 0
          if (((Time.now - host.runtime.bootTime) / 60).to_s[/^\d+\.\d{1}/].to_f) > ttl
            $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

            $logger.log('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")
          end
        end

        check_stamp = $redis.hget('vmpooler__vm__' + vm, 'check')

        if
          (!check_stamp) ||
          (((Time.now - Time.parse(check_stamp)) / 60) > $config[:config]['vm_checktime'])

          $redis.hset('vmpooler__vm__' + vm, 'check', Time.now)

          host = $vsphere[pool].find_vm(vm) ||
                 $vsphere[pool].find_vm_heavy(vm)[vm]

          if host
            if
              (host.runtime) &&
              (host.runtime.powerState) &&
              (host.runtime.powerState != 'poweredOn')

              $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

              $logger.log('d', "[!] [#{pool}] '#{vm}' appears to be powered off, removed from 'ready' queue")
            end

            if
              (host.summary.guest) &&
              (host.summary.guest.hostName) &&
              (host.summary.guest.hostName != vm)

              $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)

              $logger.log('d', "[!] [#{pool}] '#{vm}' has mismatched hostname, removed from 'ready' queue")
            end
          else
            $redis.srem('vmpooler__ready__' + pool, vm)

            $logger.log('s', "[!] [#{pool}] '#{vm}' not found in vCenter inventory, removed from 'ready' queue")
          end

          begin
            Timeout.timeout(5) do
              TCPSocket.new vm, 22
            end
          rescue
            if $redis.smove('vmpooler__ready__' + pool, 'vmpooler__completed__' + pool, vm)
              $logger.log('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")
            end
          end
        end
      end
    end

    def check_running_vm(vm, pool, ttl)
      Thread.new do
        _check_running_vm(vm, pool, ttl)
      end
    end

    def _check_running_vm(vm, pool, ttl)
      host = $vsphere[pool].find_vm(vm)

      if host
        queue_from, queue_to = 'running', 'completed'

        if (host.runtime) &&
            (host.runtime.powerState != 'poweredOn')
          move_vm_queue(pool, vm, queue_from, queue_to, 'appears to be powered off or dead')
        else
          if (host.runtime) &&
              (host.runtime.bootTime)
            ((((Time.now - host.runtime.bootTime) / 60).to_s[/^\d+\.\d{1}/].to_f) > ttl)
            move_vm_queue(pool, vm, queue_from, queue_to, "reached end of TTL after #{ttl} minutes")
          end
        end
      end
    end

    def move_vm_queue(pool, vm, queue_from, queue_to, msg)
      $redis.smove("vmpooler__#{queue_from}__#{pool}", "vmpooler__#{queue_to}__#{pool}", vm)
      $logger.log('d', "[!] [#{pool}] '#{vm}' #{msg}")
    end

    # Clone a VM
    def clone_vm(template, folder, datastore, target)
      Thread.new do
        vm = {}

        if template =~ /\//
          templatefolders = template.split('/')
          vm['template'] = templatefolders.pop
        end

        if templatefolders
          vm[vm['template']] = $vsphere[vm['template']].find_folder(templatefolders.join('/')).find(vm['template'])
        else
          fail 'Please provide a full path to the template'
        end

        if vm['template'].length == 0
          fail "Unable to find template '#{vm['template']}'!"
        end

        # Generate a randomized hostname
        o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
        vm['hostname'] = o[rand(25)] + (0...14).map { o[rand(o.length)] }.join

        # Add VM to Redis inventory ('pending' pool)
        $redis.sadd('vmpooler__pending__' + vm['template'], vm['hostname'])
        $redis.hset('vmpooler__vm__' + vm['hostname'], 'clone', Time.now)
        $redis.hset('vmpooler__vm__' + vm['hostname'], 'template', vm['template'])

        # Annotate with creation time, origin template, etc.
        configSpec = RbVmomi::VIM.VirtualMachineConfigSpec(
          annotation: JSON.pretty_generate(
              name: vm['hostname'],
              created_by: $config[:vsphere]['username'],
              base_template: vm['template'],
              creation_timestamp: Time.now.utc
           )
        )

        # Choose a clone target
        if target
          $clone_target = $vsphere[vm['template']].find_least_used_host(target)
        elsif $config[:config]['clone_target']
          $clone_target = $vsphere[vm['template']].find_least_used_host($config[:config]['clone_target'])
        end

        # Put the VM in the specified folder and resource pool
        relocateSpec = RbVmomi::VIM.VirtualMachineRelocateSpec(
          datastore: $vsphere[vm['template']].find_datastore(datastore),
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
            folder: $vsphere[vm['template']].find_folder(folder),
            name: vm['hostname'],
            spec: spec
          ).wait_for_completion
          finish = '%.2f' % (Time.now - start)

          $redis.hset('vmpooler__clone__' + Date.today.to_s, vm['template'] + ':' + vm['hostname'], finish)
          $redis.hset('vmpooler__vm__' + vm['hostname'], 'clone_time', finish)

          $logger.log('s', "[+] [#{vm['template']}] '#{vm['hostname']}' cloned from '#{vm['template']}' in #{finish} seconds")
        rescue
          $logger.log('s', "[!] [#{vm['template']}] '#{vm['hostname']}' clone appears to have failed")
          $redis.srem('vmpooler__pending__' + vm['template'], vm['hostname'])
        end

        $redis.decr('vmpooler__tasks__clone')

        begin
          $graphite.log($config[:graphite]['prefix'] + ".clone.#{vm['template']}", finish) if defined? $graphite
        rescue
        end
      end
    end

    # Destroy a VM
    def destroy_vm(vm, pool)
      Thread.new do
        $redis.srem('vmpooler__completed__' + pool, vm)
        $redis.hdel('vmpooler__active__' + pool, vm)
        $redis.hset('vmpooler__vm__' + vm, 'destroy', Time.now)

        # Auto-expire metadata key
        $redis.expire('vmpooler__vm__' + vm, ($config[:redis]['data_ttl'].to_i * 60 * 60))

        host = $vsphere[pool].find_vm(vm) ||
               $vsphere[pool].find_vm_heavy(vm)[vm]

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

          $graphite.log($config[:graphite]['prefix'] + ".destroy.#{pool}", finish) if defined? $graphite
        end
      end
    end

    def create_vm_snapshot(vm, snapshot_name)
      Thread.new do
        _create_vm_snapshot(vm, snapshot_name)
      end
    end

    def _create_vm_snapshot(vm, snapshot_name)
      host = $vsphere['snapshot_manager'].find_vm(vm) ||
             $vsphere['snapshot_manager'].find_vm_heavy(vm)[vm]

      if (host) && ((! snapshot_name.nil?) || (! snapshot_name.empty?))
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

    def revert_vm_snapshot(vm, snapshot_name)
      Thread.new do
        _revert_vm_snapshot(vm, snapshot_name)
      end
    end

    def _revert_vm_snapshot(vm, snapshot_name)
      host = $vsphere['snapshot_manager'].find_vm(vm) ||
             $vsphere['snapshot_manager'].find_vm_heavy(vm)[vm]

      if host
        snapshot = $vsphere['snapshot_manager'].find_snapshot(host, snapshot_name)

        if snapshot
          $logger.log('s', "[ ] [snapshot_manager] '#{vm}' is being reverted to snapshot '#{snapshot_name}'")

          start = Time.now

          snapshot.RevertToSnapshot_Task.wait_for_completion

          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[<] [snapshot_manager] '#{vm}' reverted to snapshot in #{finish} seconds")
        end
      end
    end

    def check_snapshot_queue
      $logger.log('d', "[*] [snapshot_manager] starting worker thread")

      $vsphere['snapshot_manager'] ||= Vmpooler::VsphereHelper.new

      $threads['snapshot_manager'] = Thread.new do
        loop do
          _check_snapshot_queue
          sleep(5)
        end
      end
    end

    def _check_snapshot_queue
      vm = $redis.spop('vmpooler__tasks__snapshot')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          create_vm_snapshot(vm_name, snapshot_name)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot appears to have failed")
        end
      end

      vm = $redis.spop('vmpooler__tasks__snapshot-revert')

      unless vm.nil?
        begin
          vm_name, snapshot_name = vm.split(':')
          revert_vm_snapshot(vm_name, snapshot_name)
        rescue
          $logger.log('s', "[!] [snapshot_manager] snapshot revert appears to have failed")
        end
      end
    end

    def check_pool(pool)
      $logger.log('d', "[*] [#{pool['name']}] starting worker thread")

      $threads[pool['name']] = Thread.new do
        $vsphere[pool['name']] ||= Vmpooler::VsphereHelper.new

        loop do
          # INVENTORY
          inventory = {}
          begin
            base = $vsphere[pool['name']].find_folder(pool['folder'])

            base.childEntity.each do |vm|
              if
                (! $redis.sismember('vmpooler__running__' + pool['name'], vm['name'])) &&
                (! $redis.sismember('vmpooler__ready__' + pool['name'], vm['name'])) &&
                (! $redis.sismember('vmpooler__pending__' + pool['name'], vm['name'])) &&
                (! $redis.sismember('vmpooler__completed__' + pool['name'], vm['name'])) &&
                (! $redis.sismember('vmpooler__discovered__' + pool['name'], vm['name']))

                $redis.sadd('vmpooler__discovered__' + pool['name'], vm['name'])

                $logger.log('s', "[?] [#{pool['name']}] '#{vm['name']}' added to 'discovered' queue")
              end

              inventory[vm['name']] = 1
            end
          rescue
          end

          # RUNNING
          $redis.smembers('vmpooler__running__' + pool['name']).each do |vm|
            if inventory[vm]
              if pool['running_ttl']
                begin
                  check_running_vm(vm, pool['name'], pool['running_ttl'])
                rescue
                end
              else
                begin
                  check_running_vm(vm, pool['name'], '720')
                rescue
                end
              end
            end
          end

          # READY
          $redis.smembers('vmpooler__ready__' + pool['name']).each do |vm|
            if inventory[vm]
              begin
                check_ready_vm(vm, pool['name'], pool['ready_ttl'] || 0)
              rescue
              end
            end
          end

          # PENDING
          $redis.smembers('vmpooler__pending__' + pool['name']).each do |vm|
            unless pool['timeout']
              if $config[:config]['timeout']
                pool['timeout'] = $config[:config]['timeout']
              else
                pool['timeout'] = 15
              end
            end

            if inventory[vm]
              begin
                check_pending_vm(vm, pool['name'], pool['timeout'])
              rescue
              end
            end
          end

          # COMPLETED
          $redis.smembers('vmpooler__completed__' + pool['name']).each do |vm|
            if inventory[vm]
              begin
                destroy_vm(vm, pool['name'])
              rescue
                $logger.log('s', "[!] [#{pool['name']}] '#{vm}' destroy appears to have failed")
                $redis.srem('vmpooler__completed__' + pool['name'], vm)
                $redis.hdel('vmpooler__active__' + pool['name'], vm)
                $redis.del('vmpooler__vm__' + vm)
              end
            else
              $logger.log('s', "[!] [#{pool['name']}] '#{vm}' not found in inventory, removed from 'completed' queue")
              $redis.srem('vmpooler__completed__' + pool['name'], vm)
              $redis.hdel('vmpooler__active__' + pool['name'], vm)
              $redis.del('vmpooler__vm__' + vm)
            end
          end

          # DISCOVERED
          $redis.smembers('vmpooler__discovered__' + pool['name']).each do |vm|
            %w(pending ready running completed).each do |queue|
              if $redis.sismember('vmpooler__' + queue + '__' + pool['name'], vm)
                $logger.log('d', "[!] [#{pool['name']}] '#{vm}' found in '#{queue}', removed from 'discovered' queue")
                $redis.srem('vmpooler__discovered__' + pool['name'], vm)
              end
            end

            if $redis.sismember('vmpooler__discovered__' + pool['name'], vm)
              $redis.smove('vmpooler__discovered__' + pool['name'], 'vmpooler__completed__' + pool['name'], vm)
            end
          end

          # LONG-RUNNING
          $redis.smembers('vmpooler__running__' + pool['name']).each do |vm|
            if $redis.hget('vmpooler__active__' + pool['name'], vm)
              running = (Time.now - Time.parse($redis.hget('vmpooler__active__' + pool['name'], vm))) / 60 / 60
              lifetime = $redis.hget('vmpooler__vm__' + vm, 'lifetime') || $config[:config]['vm_lifetime']

              if
                (lifetime.to_i > 0) &&
                (running.to_i >= lifetime.to_i)

                $redis.smove('vmpooler__running__' + pool['name'], 'vmpooler__completed__' + pool['name'], vm)

                $logger.log('d', "[!] [#{pool['name']}] '#{vm}' reached end of TTL after #{lifetime} hours")
              end
            end
          end

          # REPOPULATE
          total = $redis.scard('vmpooler__ready__' + pool['name']) +
                  $redis.scard('vmpooler__pending__' + pool['name'])

          begin
            if defined? $graphite
              $graphite.log($config[:graphite]['prefix'] + '.ready.' + pool['name'], $redis.scard('vmpooler__ready__' + pool['name']))
              $graphite.log($config[:graphite]['prefix'] + '.running.' + pool['name'], $redis.scard('vmpooler__running__' + pool['name']))
            end
          rescue
          end

          if total < pool['size']
            (1..(pool['size'] - total)).each do |_i|
              if $redis.get('vmpooler__tasks__clone').to_i < $config[:config]['task_limit']
                begin
                  $redis.incr('vmpooler__tasks__clone')

                  clone_vm(
                    pool['template'],
                    pool['folder'],
                    pool['datastore'],
                    pool['clone_target']
                  )
                rescue
                  $logger.log('s', "[!] [#{pool['name']}] clone appears to have failed")
                  $redis.decr('vmpooler__tasks__clone')
                end
              end
            end
          end

          sleep(5)
        end
      end
    end

    def execute!
      $logger.log('d', 'starting vmpooler')

      # Clear out the tasks manager, as we don't know about any tasks at this point
      $redis.set('vmpooler__tasks__clone', 0)

      loop do
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

        sleep(1)
      end
    end
  end
end
