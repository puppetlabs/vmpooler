require 'yaml'
require 'vmpooler/providers/base'

module Vmpooler
  class PoolManager
    class Provider
      class Dummy < Vmpooler::PoolManager::Provider::Base
        # Fake VM Provider for testing

        def initialize(config, logger, metrics, name, options)
          super(config, logger, metrics, name, options)
          dummyfilename = provider_config['filename']

          # This initial_state option is only intended to be used by spec tests
          @dummylist = provider_options['initial_state'].nil? ? {} : provider_options['initial_state']

          @dummylist = YAML.load_file(dummyfilename) if !dummyfilename.nil? && File.exist?(dummyfilename)

          # Even though this code is using Mutexes, it's still no 100% atomic i.e. it's still possible for
          # duplicate actions to put the @dummylist hashtable into a bad state, for example;
          # Deleting a VM while it's in the middle of adding a disk.
          @write_lock = Mutex.new

          # Create a dummy connection pool
          connpool_size    = provider_config['connection_pool_size'].nil? ? 1 : provider_config['connection_pool_size'].to_i
          connpool_timeout = provider_config['connection_pool_timeout'].nil? ? 10 : provider_config['connection_pool_timeout'].to_i
          logger.log('d', "[#{name}] ConnPool - Creating a connection pool of size #{connpool_size} with timeout #{connpool_timeout}")
          @connection_pool = Vmpooler::PoolManager::GenericConnectionPool.new(
            metrics: metrics,
            metric_prefix: "#{name}_provider_connection_pool",
            size: connpool_size,
            timeout: connpool_timeout
          ) do
            # Create a mock connection object
            new_conn = { create_timestamp: Time.now, conn_id: rand(2048).to_s }
            logger.log('d', "[#{name}] ConnPool - Creating a connection object ID #{new_conn[:conn_id]}")
            new_conn
          end
        end

        def name
          'dummy'
        end

        def vms_in_pool(pool_name)
          vmlist = []

          @connection_pool.with_metrics do |_conn|
            get_dummy_pool_object(pool_name).each do |vm|
              vmlist << { 'name' => vm['name'] }
            end
          end

          vmlist
        end

        def get_vm_host(pool_name, vm_name)
          current_vm = nil
          @connection_pool.with_metrics do |_conn|
            current_vm = get_dummy_vm(pool_name, vm_name)
          end

          current_vm.nil? ? raise("VM #{vm_name} does not exist") : current_vm['vm_host']
        end

        def find_least_used_compatible_host(pool_name, vm_name)
          current_vm = nil
          @connection_pool.with_metrics do |_conn|
            current_vm = get_dummy_vm(pool_name, vm_name)
          end

          # Unless migratevm_couldmove_percent is specified, don't migrate
          return current_vm['vm_host'] if provider_config['migratevm_couldmove_percent'].nil?

          # Only migrate if migratevm_couldmove_percent is met
          return current_vm['vm_host'] if rand(1..100) > provider_config['migratevm_couldmove_percent']

          # Simulate a 10 node cluster and randomly pick a different one
          new_host = 'HOST' + rand(1..10).to_s while new_host == current_vm['vm_host']

          new_host
        end

        def migrate_vm_to_host(pool_name, vm_name, dest_host_name)
          @connection_pool.with_metrics do |_conn|
            current_vm = get_dummy_vm(pool_name, vm_name)

            # Inject migration delay
            unless provider_config['migratevm_max_time'].nil?
              migrate_time = 1 + rand(provider_config['migratevm_max_time'])
              sleep(migrate_time)
            end

            # Inject clone failure
            unless provider_config['migratevm_fail_percent'].nil?
              raise('Dummy Failure for migratevm_fail_percent') if rand(1..100) <= provider_config['migratevm_fail_percent']
            end

            @write_lock.synchronize do
              current_vm = get_dummy_vm(pool_name, vm_name)
              current_vm['vm_host'] = dest_host_name
              write_backing_file
            end
          end

          true
        end

        def get_vm(pool_name, vm_name)
          obj = {}
          @connection_pool.with_metrics do |_conn|
            dummy = get_dummy_vm(pool_name, vm_name)
            return nil if dummy.nil?

            # Randomly power off the VM
            unless dummy['powerstate'] != 'PoweredOn' || provider_config['getvm_poweroff_percent'].nil?
              if rand(1..100) <= provider_config['getvm_poweroff_percent']
                @write_lock.synchronize do
                  dummy = get_dummy_vm(pool_name, vm_name)
                  dummy['powerstate'] = 'PoweredOff'
                  write_backing_file
                end
                logger.log('d', "[ ] [#{dummy['poolname']}] '#{dummy['name']}' is being Dummy Powered Off")
              end
            end

            # Randomly rename the host
            unless dummy['hostname'] != dummy['name'] || provider_config['getvm_rename_percent'].nil?
              if rand(1..100) <= provider_config['getvm_rename_percent']
                @write_lock.synchronize do
                  dummy = get_dummy_vm(pool_name, vm_name)
                  dummy['hostname'] = 'DUMMY' + dummy['name']
                  write_backing_file
                end
                logger.log('d', "[ ] [#{dummy['poolname']}] '#{dummy['name']}' is being Dummy renamed")
              end
            end

            obj['name'] = dummy['name']
            obj['hostname'] = dummy['hostname']
            obj['boottime'] = dummy['boottime']
            obj['template'] = dummy['template']
            obj['poolname'] = dummy['poolname']
            obj['powerstate'] = dummy['powerstate']
            obj['snapshots'] = dummy['snapshots']
          end

          obj
        end

        def create_vm(pool_name, dummy_hostname)
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?

          template_name = pool['template']

          vm = {}
          vm['name'] = dummy_hostname
          vm['hostname'] = dummy_hostname
          vm['domain'] = 'dummy.local'
          # 'vm_template' is the name of the template to use to clone the VM from  <----- Do we need this?!?!?
          vm['vm_template'] = template_name
          # 'template' is the Template name in VM Pooler API, in our case that's the poolname.
          vm['template'] = pool_name
          vm['poolname'] = pool_name
          vm['ready'] = false
          vm['boottime'] = Time.now
          vm['powerstate'] = 'PoweredOn'
          vm['vm_host'] = 'HOST1'
          vm['dummy_state'] = 'UNKNOWN'
          vm['snapshots'] = []
          vm['disks'] = []

          # Make sure the pool exists in the dummy list
          @write_lock.synchronize do
            get_dummy_pool_object(pool_name)
            @dummylist['pool'][pool_name] << vm
            write_backing_file
          end

          logger.log('d', "[ ] [#{pool_name}] '#{dummy_hostname}' is being cloned from '#{template_name}'")

          @connection_pool.with_metrics do |_conn|
            # Inject clone time delay
            unless provider_config['createvm_max_time'].nil?
              @write_lock.synchronize do
                vm['dummy_state'] = 'CLONING'
                write_backing_file
              end
              clone_time = 1 + rand(provider_config['createvm_max_time'])
              sleep(clone_time)
            end

            begin
              # Inject clone failure
              unless provider_config['createvm_fail_percent'].nil?
                raise('Dummy Failure for createvm_fail_percent') if rand(1..100) <= provider_config['createvm_fail_percent']
              end

              # Assert the VM is ready for use
              @write_lock.synchronize do
                vm['dummy_state'] = 'RUNNING'
                write_backing_file
              end
            rescue StandardError => _e
              @write_lock.synchronize do
                remove_dummy_vm(pool_name, dummy_hostname)
                write_backing_file
              end
              raise
            end
          end

          get_vm(pool_name, dummy_hostname)
        end

        def create_disk(pool_name, vm_name, disk_size)
          @connection_pool.with_metrics do |_conn|
            vm_object = get_dummy_vm(pool_name, vm_name)
            raise("VM #{vm_name} does not exist  in Pool #{pool_name} for the provider #{name}") if vm_object.nil?

            # Inject create time delay
            unless provider_config['createdisk_max_time'].nil?
              delay = 1 + rand(provider_config['createdisk_max_time'])
              sleep(delay)
            end

            # Inject create failure
            unless provider_config['createdisk_fail_percent'].nil?
              raise('Dummy Failure for createdisk_fail_percent') if rand(1..100) <= provider_config['createdisk_fail_percent']
            end

            @write_lock.synchronize do
              vm_object = get_dummy_vm(pool_name, vm_name)
              vm_object['disks'] << disk_size
              write_backing_file
            end
          end

          true
        end

        def create_snapshot(pool_name, vm_name, snapshot_name)
          @connection_pool.with_metrics do |_conn|
            vm_object = get_dummy_vm(pool_name, vm_name)
            raise("VM #{vm_name} does not exist  in Pool #{pool_name} for the provider #{name}") if vm_object.nil?

            # Inject create time delay
            unless provider_config['createsnapshot_max_time'].nil?
              delay = 1 + rand(provider_config['createsnapshot_max_time'])
              sleep(delay)
            end

            # Inject create failure
            unless provider_config['createsnapshot_fail_percent'].nil?
              raise('Dummy Failure for createsnapshot_fail_percent') if rand(1..100) <= provider_config['createsnapshot_fail_percent']
            end

            @write_lock.synchronize do
              vm_object = get_dummy_vm(pool_name, vm_name)
              vm_object['snapshots'] << snapshot_name
              write_backing_file
            end
          end

          true
        end

        def revert_snapshot(pool_name, vm_name, snapshot_name)
          vm_object = nil
          @connection_pool.with_metrics do |_conn|
            vm_object = get_dummy_vm(pool_name, vm_name)
            raise("VM #{vm_name} does not exist  in Pool #{pool_name} for the provider #{name}") if vm_object.nil?

            # Inject create time delay
            unless provider_config['revertsnapshot_max_time'].nil?
              delay = 1 + rand(provider_config['revertsnapshot_max_time'])
              sleep(delay)
            end

            # Inject create failure
            unless provider_config['revertsnapshot_fail_percent'].nil?
              raise('Dummy Failure for revertsnapshot_fail_percent') if rand(1..100) <= provider_config['revertsnapshot_fail_percent']
            end
          end

          vm_object['snapshots'].include?(snapshot_name)
        end

        def destroy_vm(pool_name, vm_name)
          @connection_pool.with_metrics do |_conn|
            vm = get_dummy_vm(pool_name, vm_name)
            return false if vm.nil?
            return false if vm['poolname'] != pool_name

            # Shutdown down the VM if it's poweredOn
            if vm['powerstate'] == 'PoweredOn'
              logger.log('d', "[ ] [#{pool_name}] '#{vm_name}' is being shut down")

              # Inject shutdown delay time
              unless provider_config['destroyvm_max_shutdown_time'].nil?
                shutdown_time = 1 + rand(provider_config['destroyvm_max_shutdown_time'])
                sleep(shutdown_time)
              end

              @write_lock.synchronize do
                vm = get_dummy_vm(pool_name, vm_name)
                vm['powerstate'] = 'PoweredOff'
                write_backing_file
              end
            end

            # Inject destroy VM delay
            unless provider_config['destroyvm_max_time'].nil?
              destroy_time = 1 + rand(provider_config['destroyvm_max_time'])
              sleep(destroy_time)
            end

            # Inject destroy VM failure
            unless provider_config['destroyvm_fail_percent'].nil?
              raise('Dummy Failure for migratevm_fail_percent') if rand(1..100) <= provider_config['destroyvm_fail_percent']
            end

            # 'Destroy' the VM
            @write_lock.synchronize do
              remove_dummy_vm(pool_name, vm_name)
              write_backing_file
            end
          end

          true
        end

        def vm_ready?(pool_name, vm_name)
          @connection_pool.with_metrics do |_conn|
            vm_object = get_dummy_vm(pool_name, vm_name)
            return false if vm_object.nil?
            return false if vm_object['poolname'] != pool_name
            return true if vm_object['ready']

            timeout = provider_config['is_ready_timeout'] || 5

            Timeout.timeout(timeout) do
              while vm_object['dummy_state'] != 'RUNNING'
                sleep(2)
                vm_object = get_dummy_vm(pool_name, vm_name)
              end
            end

            # Simulate how long it takes from a VM being powered on until
            # it's ready to receive a connection
            sleep(2)

            unless provider_config['vmready_fail_percent'].nil?
              raise('Dummy Failure for vmready_fail_percent') if rand(1..100) <= provider_config['vmready_fail_percent']
            end

            @write_lock.synchronize do
              vm_object['ready'] = true
              write_backing_file
            end
          end

          true
        end

        private

        # Note - NEVER EVER use the @write_lock object in the private methods!!!!  Deadlocks will ensue

        def remove_dummy_vm(pool_name, vm_name)
          return if @dummylist['pool'][pool_name].nil?

          new_poollist = @dummylist['pool'][pool_name].delete_if { |vm| vm['name'] == vm_name }
          @dummylist['pool'][pool_name] = new_poollist
        end

        # Get's the pool config safely from the in-memory hashtable
        def get_dummy_pool_object(pool_name)
          @dummylist['pool'] = {} if @dummylist['pool'].nil?
          @dummylist['pool'][pool_name] = [] if @dummylist['pool'][pool_name].nil?

          @dummylist['pool'][pool_name]
        end

        def get_dummy_vm(pool_name, vm_name)
          return nil if @dummylist['pool'][pool_name].nil?

          @dummylist['pool'][pool_name].each do |poolvm|
            return poolvm if poolvm['name'] == vm_name
          end

          nil
        end

        def write_backing_file
          dummyfilename = provider_config['filename']
          return if dummyfilename.nil?

          File.open(dummyfilename, 'w') { |file| file.write(YAML.dump(@dummylist)) }
        end
      end
    end
  end
end
