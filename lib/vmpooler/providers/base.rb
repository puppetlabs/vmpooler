# frozen_string_literal: true

module Vmpooler
  class PoolManager
    class Provider
      class Base
        # These defs must be overidden in child classes

        # Helper Methods
        # Global Logger object
        attr_reader :logger
        # Global Metrics object
        attr_reader :metrics
        # Provider options passed in during initialization
        attr_reader :provider_options

        def initialize(config, logger, metrics, redis_connection_pool, name, options)
          @config = config
          @logger = logger
          @metrics = metrics
          @redis = redis_connection_pool
          @provider_name = name

          # Ensure that there is not a nil provider configuration
          @config[:providers] = {} if @config[:providers].nil?
          @config[:providers][@provider_name] = {} if provider_config.nil?

          # Ensure that there is not a nil pool configuration
          @config[:pools] = {} if @config[:pools].nil?

          @provider_options = options
          logger.log('s', "[!] Creating provider '#{name}'")
        end

        # Helper Methods

        # inputs
        #  [String] pool_name : Name of the pool to get the configuration
        # returns
        #   [Hashtable] : The pools configuration from the config file.  Returns nil if the pool does not exist
        def pool_config(pool_name)
          # Get the configuration of a specific pool
          @config[:pools].each do |pool|
            return pool if pool['name'] == pool_name
          end

          nil
        end

        # returns
        #   [Hashtable] : This provider's configuration from the config file.  Returns nil if the provider does not exist
        def provider_config
          @config[:providers].each do |provider|
            # Convert the symbol from the config into a string for comparison
            return (provider[1].nil? ? {} : provider[1]) if provider[0].to_s == @provider_name
          end

          nil
        end

        # returns
        #   [Hashtable] : The entire VMPooler configuration
        def global_config
          # This entire VM Pooler config
          @config
        end

        # returns
        #   [String] : Name of the provider service
        def name
          @provider_name
        end

        # returns
        #   Array[String] : Array of pool names this provider services
        def provided_pools
          list = []
          @config[:pools].each do |pool|
            list << pool['name'] if pool['provider'] == name
          end
          list
        end

        # Pool Manager Methods

        # inputs
        #  [String] pool_name : Name of the pool
        # returns
        #   Array[Hashtable]
        #     Hash contains:
        #       'name' => [String] Name of VM
        def vms_in_pool(_pool_name)
          raise("#{self.class.name} does not implement vms_in_pool")
        end

        # inputs
        #   [String]pool_name : Name of the pool
        #   [String] vm_name  : Name of the VM
        # returns
        #   [String] : Name of the host computer running the vm.  If this is not a Virtual Machine, it returns the vm_name
        def get_vm_host(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement get_vm_host")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM
        # returns
        #   [String] : Name of the most appropriate host computer to run this VM.  Useful for load balancing VMs in a cluster
        #                If this is not a Virtual Machine, it returns the vm_name
        def find_least_used_compatible_host(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement find_least_used_compatible_host")
        end

        # inputs
        #   [String] pool_name      : Name of the pool
        #   [String] vm_name        : Name of the VM to migrate
        #   [String] dest_host_name : Name of the host to migrate `vm_name` to
        # returns
        #   [Boolean] : true on success or false on failure
        def migrate_vm_to_host(_pool_name, _vm_name, _dest_host_name)
          raise("#{self.class.name} does not implement migrate_vm_to_host")
        end

        # inputs
        #   [String] pool_name      : Name of the pool
        #   [String] vm_name        : Name of the VM to migrate
        #   [Class] redis           : Redis object
        def migrate_vm(_pool_name, _vm_name, _redis)
          raise("#{self.class.name} does not implement migrate_vm")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to find
        # returns
        #   nil if VM doesn't exist
        #   [Hastable] of the VM
        #    [String] name       : Name of the VM
        #    [String] hostname   : Name reported by Vmware tools (host.summary.guest.hostName)
        #    [String] template   : This is the name of template exposed by the API.  It must _match_ the poolname
        #    [String] poolname   : Name of the pool the VM is located
        #    [Time]   boottime   : Time when the VM was created/booted
        #    [String] powerstate : Current power state of a VM.  Valid values (as per vCenter API)
        #                            - 'PoweredOn','PoweredOff'
        def get_vm(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement get_vm")
        end

        # inputs
        #   [String] pool       : Name of the pool
        #   [String] new_vmname : Name to give the new VM
        # returns
        #   [Hashtable] of the VM as per get_vm
        #   Raises RuntimeError if the pool_name is not supported by the Provider
        def create_vm(_pool_name, _new_vmname)
          raise("#{self.class.name} does not implement create_vm")
        end

        # inputs
        #   [String]  pool_name  : Name of the pool
        #   [String]  vm_name    : Name of the VM to create the disk on
        #   [Integer] disk_size  : Size of the disk to create in Gigabytes (GB)
        # returns
        #   [Boolean] : true if success, false if disk could not be created
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        def create_disk(_pool_name, _vm_name, _disk_size)
          raise("#{self.class.name} does not implement create_disk")
        end

        # inputs
        #   [String] pool_name         : Name of the pool
        #   [String] new_vmname        : Name of the VM to create the snapshot on
        #   [String] new_snapshot_name : Name of the new snapshot to create
        # returns
        #   [Boolean] : true if success, false if snapshot could not be created
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        def create_snapshot(_pool_name, _vm_name, _new_snapshot_name)
          raise("#{self.class.name} does not implement create_snapshot")
        end

        # inputs
        #   [String] pool_name     : Name of the pool
        #   [String] new_vmname    : Name of the VM to restore
        #   [String] snapshot_name : Name of the snapshot to restore to
        # returns
        #   [Boolean] : true if success, false if snapshot could not be revertted
        #   Raises RuntimeError if the Pool does not exist
        #   Raises RuntimeError if the VM does not exist
        #   Raises RuntimeError if the snapshot does not exist
        def revert_snapshot(_pool_name, _vm_name, _snapshot_name)
          raise("#{self.class.name} does not implement revert_snapshot")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to destroy
        # returns
        #   [Boolean] : true if success, false on error. Should returns true if the VM is missing
        def destroy_vm(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement destroy_vm")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to check if ready
        # returns
        #   [Boolean] : true if ready, false if not
        def vm_ready?(_pool_name, _vm_name)
          raise("#{self.class.name} does not implement vm_ready?")
        end

        # inputs
        #   [String] pool_name : Name of the pool
        #   [String] vm_name   : Name of the VM to check if it exists
        # returns
        #   [Boolean] : true if it exists, false if not
        def vm_exists?(pool_name, vm_name)
          !get_vm(pool_name, vm_name).nil?
        end

        # inputs
        #   [Hash] pool : Configuration for the pool
        # returns
        #   nil when successful. Raises error when encountered
        def create_template_delta_disks(_pool)
          raise("#{self.class.name} does not implement create_template_delta_disks")
        end

        # inputs
        #   [String] provider_name : Name of the provider
        # returns
        #   Hash of folders
        def get_target_datacenter_from_config(_provider_name)
          raise("#{self.class.name} does not implement get_target_datacenter_from_config")
        end

        def purge_unconfigured_resources(_whitelist)
          raise("#{self.class.name} does not implement purge_unconfigured_resources")
        end

        # DEPRECATED if a provider does not implement the new method, it will hit this base class method
        # and return a deprecation message
        def purge_unconfigured_folders(_deprecated, _deprecated2, whitelist)
          logger.log('s', "[!] purge_unconfigured_folders was renamed to purge_unconfigured_resources, please update your provider implementation")
          purge_unconfigured_resources(whitelist)
        end
      end
    end
  end
end
