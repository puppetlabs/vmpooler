module Vmpooler
  class PoolManager
    class Provider
      class Base
        # These defs must be overidden in child classes

        def initialize(options)
          @provider_options = options
        end

        # returns
        #   [String] Name of the provider service
        def name
          'base'
        end

        # inputs
        #  pool : hashtable from config file
        # returns
        #   hashtable
        #     name : name of the device   <---- TODO is this all?
        def vms_in_pool(pool)
          fail "#{self.class.name} does not implement vms_in_pool"
        end

        # inputs
        #   vm_name: string
        # returns
        #    [String] hostname   = Name of the host computer running the vm.  If this is not a Virtual Machine, it returns the vm_name
        def get_vm_host(vm_name)
          fail "#{self.class.name} does not implement get_vm_host"
        end

        # inputs
        #   vm_name: string
        # returns
        #    [String] hostname   = Name of the most appropriate host computer to run this VM.  Useful for load balancing VMs in a cluster
        #                          If this is not a Virtual Machine, it returns the vm_name
        def find_least_used_compatible_host(vm_name)
          fail "#{self.class.name} does not implement find_least_used_compatible_host"
        end

        # inputs
        #   vm_name: string
        #   dest_host_name: string (Name of the host to migrate `vm_name` to)
        # returns
        #    [Boolean] Returns true on success or false on failure
        def migrate_vm_to_host(vm_name, dest_host_name)
          fail "#{self.class.name} does not implement migrate_vm_to_host"
        end

        # inputs
        #   vm_name: string
        # returns
        #   nil if it doesn't exist
        #   Hastable of the VM
        #    [String] name       = Name of the VM
        #    [String] hostname   = Name reported by Vmware tools (host.summary.guest.hostName)
        #    [String] template   = This is the name of template exposed by the API.  It must _match_ the poolname
        #    [String] poolname   = Name of the pool the VM is located
        #    [Time]   boottime   = Time when the VM was created/booted
        #    [String] powerstate = Current power state of a VM.  Valid values (as per vCenter API)
        #                            - 'PoweredOn','PoweredOff'
        def get_vm(vm_name)
          fail "#{self.class.name} does not implement get_vm"
        end

        # inputs
        #   pool : hashtable from config file
        #   new_vmname : string      Name the new VM should use
        # returns
        #   Hashtable of the VM as per get_vm
        def create_vm(pool,new_vmname)
          fail "#{self.class.name} does not implement create_vm"
        end

        # inputs
        #   vm_name: string
        #   pool: string
        # returns
        #   boolean : true if success, false on error
        def destroy_vm(vm_name,pool)
          fail "#{self.class.name} does not implement destroy_vm"
        end

        # inputs
        #    vm  : string
        #    pool: string
        # timeout: int (Seconds)
        # returns
        #   result: boolean
        def is_vm_ready?(vm,pool,timeout)
          fail "#{self.class.name} does not implement is_vm_ready?"
        end

        # inputs
        #    vm : string
        # returns
        #   result: boolean
        def vm_exists?(vm)
          !get_vm(vm).nil?
        end

      end
    end
  end
end
