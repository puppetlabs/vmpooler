require 'yaml'

module Vmpooler
  class PoolManager
    class BackingService
      class Dummy < Vmpooler::PoolManager::BackingService::Base

        # Fake VM backing service for testing, with initial configuration set in a simple text YAML filename
        def initialize(options)
          dummyfilename = options['filename']

          # TODO Accessing @dummylist is not thread safe :-(  Mutexes?
          @dummylist = {}

          if !dummyfilename.nil? && File.exists?(dummyfilename)
            @dummylist ||= YAML.load_file(dummyfilename)
          end
        end

        def vms_in_pool(pool)
          get_pool_object(pool['name']).each do |vm|
            vm
          end
        end

        def get_vm(vm)
          dummy = get_dummy_vm(vm)
          return nil if dummy.nil?

          obj = {}
          # TODO Randomly power off the vm?
          # TODO Randomly change the hostname of the vm?
          obj['hostname'] = dummy['name']
          obj['boottime'] = dummy['boottime']
          obj['template'] = dummy['template']
          obj['poolname'] = dummy['poolname']
          obj['powerstate'] = dummy['powerstate']

          obj
        end

        def vm_exists?(vm)
          !get_vm(vm).nil?
        end

        def find_least_used_compatible_host(vm_name)
          current_vm = get_dummy_vm(vm_name)

          # TODO parameterise this  (75% chance it will not migrate)
          return current_vm['vm_host'] if 1 + rand(100) < 75 

          # TODO paramtise this (Simulates a 10 node cluster)
          (1 + rand(10)).to_s
        end

        def get_vm_host(vm_name)
          current_vm = get_dummy_vm(vm_name)

          current_vm['vm_host']
        end

        def migrate_vm_to_host(vm_name, dest_host_name)
          current_vm = get_dummy_vm(vm_name)

          # TODO do I need fake a random sleep for ready?
          # TODO Should I inject a random error?

          sleep(1)
          current_vm['vm_host'] = dest_host_name

          true
        end

        def is_vm_ready?(vm,pool,timeout)
          host = get_dummy_vm(vm)
          if !host then return false end
          if host['poolname'] != pool then return false end
          if vm['ready'] then return true end
          # TODO do I need fake a random sleep for ready?
          # TODO Should I inject a random error?
          sleep(2)
          host['ready'] = true

          true
        end

        def create_vm(pool)
          # This is an async operation
          # This code just clones a VM and starts it
          # Later checking will move it from the pending to ready queue
          Thread.new do
            begin
              template_name = pool['template']
              pool_name = pool['name']

              # Generate a randomized hostname
              o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
              dummy_hostname = $config[:config]['prefix'] + o[rand(25)] + (0...14).map { o[rand(o.length)] }.join

              vm = {}
              vm['name'] = dummy_hostname
              vm['hostname'] = dummy_hostname
              vm['domain']  = 'dummy.local'
              vm['vm_template'] = template_name
              # 'template' is the Template in API, not the template to create the VM ('vm_template')
              vm['template'] = pool_name
              vm['poolname'] = pool_name
              vm['ready'] = false
              vm['boottime'] = Time.now
              vm['powerstate'] = 'PoweredOn'
              vm['vm_host'] = '1'
              get_pool_object(pool_name)
              @dummylist['pool'][pool_name] << vm

              # Add VM to Redis inventory ('pending' pool)
              $redis.sadd('vmpooler__pending__' + pool_name, vm['hostname'])
              $redis.hset('vmpooler__vm__' + vm['hostname'], 'clone', Time.now)
              $redis.hset('vmpooler__vm__' + vm['hostname'], 'template', vm['template'])

              $logger.log('d', "[ ] [#{pool_name}] '#{dummy_hostname}' is being cloned from '#{template_name}'")
              begin
                start = Time.now

                # TODO do I need fake a random sleep to clone
                sleep(2)

                # TODO Inject random clone failure
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
              dummy_hostname
            rescue => err
              $logger.log('s', "[!] [#{vm['template']}] '#{vm['hostname']}' failed while preparing to clone with an error: #{err}")
              raise
            end
          end
        end

        def destroy_vm(vm_name,pool)
          vm = get_dummy_vm(vm_name)
          if !vm then return false end
          if vm['poolname'] != pool then return false end

          start = Time.now

          # Shutdown down the VM if it's poweredOn
          if vm['powerstate'] = 'PoweredOn'
            $logger.log('d', "[ ] [#{pool}] '#{vm_name}' is being shut down")
            # TODO Use random shutdown interval
            sleep(2)
            vm['powerstate'] = 'PoweredOff'
          end

          # 'Destroy' the VM
          new_poollist = @dummylist['pool'][pool].delete_if { |vm| vm['name'] == vm_name }
          @dummylist['pool'][pool] = new_poollist

          # TODO Use random destruction interval
          sleep(2)

          finish = '%.2f' % (Time.now - start)

          $logger.log('s', "[-] [#{pool}] '#{vm_name}' destroyed in #{finish} seconds")
          $metrics.timing("destroy.#{pool}", finish)
        end

        private
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