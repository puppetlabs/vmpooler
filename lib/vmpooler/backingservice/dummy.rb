require 'yaml'

module Vmpooler
  class PoolManager
    class BackingService
      class Dummy < Vmpooler::PoolManager::BackingService::Base

        # Fake VM backing service for testing, with initial configuration set in a simple text YAML filename
        #   or via YAML in the config file
        def initialize(options)
          super(options)

          dummyfilename = options['filename']

          # TODO Accessing @dummylist is not thread safe :-(  Mutexes?

          # This initial_state option is only intended to be used by spec tests
          @dummylist = options['initial_state'].nil? ? {} : options['initial_state']

          if !dummyfilename.nil? && File.exists?(dummyfilename)
            @dummylist ||= YAML.load_file(dummyfilename)
          end
        end

        def vms_in_pool(pool)
          get_pool_object(pool['name']).each do |vm|
            vm
          end
        end

        def name
          'dummy'
        end

        def get_vm(vm)
          dummy = get_dummy_vm(vm)
          return nil if dummy.nil?

          # Randomly power off the VM
          unless dummy['powerstate'] != 'PoweredOn' || @options['getvm_poweroff_percent'].nil?
            if 1 + rand(100) <= @options['getvm_poweroff_percent']
              dummy['powerstate'] = 'PoweredOff'
              $logger.log('d', "[ ] [#{dummy['poolname']}] '#{dummy['name']}' is being Dummy Powered Off")
            end
          end

          # Randomly rename the host
          unless dummy['hostname'] != dummy['name'] || @options['getvm_rename_percent'].nil?
            if 1 + rand(100) <= @options['getvm_rename_percent']
              dummy['hostname'] = 'DUMMY' + dummy['name']
              $logger.log('d', "[ ] [#{dummy['poolname']}] '#{dummy['name']}' is being Dummy renamed")
            end
          end

          obj = {}
          obj['name'] = dummy['name']
          obj['hostname'] = dummy['hostname']
          obj['boottime'] = dummy['boottime']
          obj['template'] = dummy['template']
          obj['poolname'] = dummy['poolname']
          obj['powerstate'] = dummy['powerstate']

          obj
        end

        def find_least_used_compatible_host(vm_name)
          current_vm = get_dummy_vm(vm_name)

          # Unless migratevm_couldmove_percent is specified, don't migrate
          return current_vm['vm_host'] if @options['migratevm_couldmove_percent'].nil?

          # Only migrate if migratevm_couldmove_percent is met
          return current_vm['vm_host'] if 1 + rand(100) > @options['migratevm_couldmove_percent']
          
          # Simulate a 10 node cluster and randomly pick a different one
          new_host = "HOST" + (1 + rand(10)).to_s while new_host == current_vm['vm_host']

          new_host
        end

        def get_vm_host(vm_name)
          current_vm = get_dummy_vm(vm_name)

          current_vm.nil? ? fail("VM #{vm_name} does not exist") : current_vm['vm_host']
        end

        def migrate_vm_to_host(vm_name, dest_host_name)
          current_vm = get_dummy_vm(vm_name)

          # Inject migration delay
          unless @options['migratevm_max_time'].nil?
            migrate_time = 1 + rand(@options['migratevm_max_time'])
            sleep(migrate_time)
          end

          # Inject clone failure
          unless @options['migratevm_fail_percent'].nil?
            fail "Dummy Failure for migratevm_fail_percent" if 1 + rand(100) <= @options['migratevm_fail_percent']
          end

          current_vm['vm_host'] = dest_host_name

          true
        end

        def is_vm_ready?(vm,pool,timeout)
          host = get_dummy_vm(vm)
          if !host then return false end
          if host['poolname'] != pool then return false end
          if host['ready'] then return true end

          Timeout.timeout(timeout) do
            while host['dummy_state'] != 'RUNNING'
              sleep(2)
              host = get_dummy_vm(vm)
            end
          end

          # Simulate how long it takes from a VM being powered on until
          # it's ready to receive a connection
          sleep(2)

          unless @options['vmready_fail_percent'].nil?
            fail "Dummy Failure for vmready_fail_percent" if 1 + rand(100) <= @options['vmready_fail_percent']
          end

          host['ready'] = true
          true
        end

        def create_vm(pool,dummy_hostname)
          template_name = pool['template']
          pool_name = pool['name']

          vm = {}
          vm['name'] = dummy_hostname
          vm['hostname'] = dummy_hostname
          vm['domain']  = 'dummy.local'
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
          get_pool_object(pool_name)
          @dummylist['pool'][pool_name] << vm

          $logger.log('d', "[ ] [#{pool_name}] '#{dummy_hostname}' is being cloned from '#{template_name}'")
          begin
            # Inject clone time delay
            unless @options['createvm_max_time'].nil?
              vm['dummy_state'] = 'CLONING'
              clone_time = 1 + rand(@options['createvm_max_time'])
              sleep(clone_time)
            end

            # Inject clone failure
            unless @options['createvm_fail_percent'].nil?
              fail "Dummy Failure for createvm_fail_percent" if 1 + rand(100) <= @options['createvm_fail_percent']
            end

            # Assert the VM is ready for use
            vm['dummy_state'] = 'RUNNING'
          rescue => err
            remove_dummy_vm(dummy_hostname,pool_name)
            raise
          end

          get_vm(dummy_hostname)
        end

        def destroy_vm(vm_name,pool)
          vm = get_dummy_vm(vm_name)
          if !vm then return false end
          if vm['poolname'] != pool then return false end

          # Shutdown down the VM if it's poweredOn
          if vm['powerstate'] = 'PoweredOn'
            $logger.log('d', "[ ] [#{pool}] '#{vm_name}' is being shut down")

            # Inject shutdown delay time
            unless @options['destroyvm_max_shutdown_time'].nil?
              shutdown_time = 1 + rand(@options['destroyvm_max_shutdown_time'])
              sleep(shutdown_time)
            end

            vm['powerstate'] = 'PoweredOff'
          end

          # Inject destroy VM delay
          unless @options['destroyvm_max_time'].nil?
            destroy_time = 1 + rand(@options['destroyvm_max_time'])
            sleep(destroy_time)
          end

          # Inject destroy VM failure
          unless @options['destroyvm_fail_percent'].nil?
            fail "Dummy Failure for migratevm_fail_percent" if 1 + rand(100) <= @options['destroyvm_fail_percent']
          end

          # 'Destroy' the VM
          remove_dummy_vm(vm_name,pool)

          true
        end

        private
        def remove_dummy_vm(vm_name,pool)
          return if @dummylist['pool'][pool].nil?
          new_poollist = @dummylist['pool'][pool].delete_if { |vm| vm['name'] == vm_name }
          @dummylist['pool'][pool] = new_poollist
        end

        # Get's the pool config safely from the in-memory hashtable
        def get_pool_object(pool_name)
          @dummylist['pool'] = {} if @dummylist['pool'].nil?
          @dummylist['pool'][pool_name] = [] if @dummylist['pool'][pool_name].nil?
          
          return @dummylist['pool'][pool_name]
        end

        def get_dummy_vm(vm)
          @dummylist['pool'].keys.each do |poolname|
            @dummylist['pool'][poolname].each do |poolvm|
              return poolvm if poolvm['name'] == vm
            end
          end

          nil
        end
      end
    end
  end
end