module Vmpooler
  class PoolManager
    class Provider
      class VSphere < Vmpooler::PoolManager::Provider::Base
        # The connection_pool method is normally used only for testing
        attr_reader :connection_pool

        def initialize(config, logger, metrics, name, options)
          super(config, logger, metrics, name, options)

          task_limit = global_config[:config].nil? || global_config[:config]['task_limit'].nil? ? 10 : global_config[:config]['task_limit'].to_i
          # The default connection pool size is:
          # Whatever is biggest from:
          #   - How many pools this provider services
          #   - Maximum number of cloning tasks allowed
          #   - Need at least 2 connections so that a pool can have inventory functions performed while cloning etc.
          default_connpool_size = [provided_pools.count, task_limit, 2].max
          connpool_size = provider_config['connection_pool_size'].nil? ? default_connpool_size : provider_config['connection_pool_size'].to_i
          # The default connection pool timeout should be quite large - 60 seconds
          connpool_timeout = provider_config['connection_pool_timeout'].nil? ? 60 : provider_config['connection_pool_timeout'].to_i
          logger.log('d', "[#{name}] ConnPool - Creating a connection pool of size #{connpool_size} with timeout #{connpool_timeout}")
          @connection_pool = Vmpooler::PoolManager::GenericConnectionPool.new(
            metrics: metrics,
            metric_prefix: "#{name}_provider_connection_pool",
            size: connpool_size,
            timeout: connpool_timeout
          ) do
            logger.log('d', "[#{name}] Connection Pool - Creating a connection object")
            # Need to wrap the vSphere connection object in another object. The generic connection pooler will preserve
            # the object reference for the connection, which means it cannot "reconnect" by creating an entirely new connection
            # object.  Instead by wrapping it in a Hash, the Hash object reference itself never changes but the content of the
            # Hash can change, and is preserved across invocations.
            new_conn = connect_to_vsphere
            { connection: new_conn }
          end
          @provider_hosts = {}
          @provider_hosts_lock = Mutex.new
        end

        # name of the provider class
        def name
          'vsphere'
        end

        def vms_in_pool(pool_name)
          vms = []
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            foldername = pool_config(pool_name)['folder']
            folder_object = find_folder(foldername, connection, get_target_datacenter_from_config(pool_name))

            return vms if folder_object.nil?

            folder_object.childEntity.each do |vm|
              vms << { 'name' => vm.name }
            end
          end
          vms
        end

        def select_target_hosts(target, cluster, datacenter)
          percentage = 100
          dc = "#{datacenter}_#{cluster}"
          @provider_hosts_lock.synchronize do
            begin
              target[dc] = {} unless target.key?(dc)
              target[dc]['checking'] = true
              hosts_hash = find_least_used_hosts(cluster, datacenter, percentage)
              target[dc] = hosts_hash
            rescue => _err
              target[dc] = {}
              raise(_err)
            ensure
              target[dc]['check_time_finished'] = Time.now
            end
          end
        end

        def run_select_hosts(pool_name, target)
          now = Time.now
          max_age = @config[:config]['host_selection_max_age'] || 60
          loop_delay = 5
          datacenter = get_target_datacenter_from_config(pool_name)
          cluster = get_target_cluster_from_config(pool_name)
          raise("cluster for pool #{pool_name} cannot be identified") if cluster.nil?
          raise("datacenter for pool #{pool_name} cannot be identified") if datacenter.nil?
          dc = "#{datacenter}_#{cluster}"
          select_target_hosts(target, cluster, datacenter) unless target.key?(dc)
          if target[dc].key?('checking')
            wait_for_host_selection(dc, target, loop_delay, max_age)
          end
          if target[dc].key?('check_time_finished')
            if now - target[dc]['check_time_finished'] > max_age
              select_target_hosts(target, cluster, datacenter)
            end
          end
        end

        def wait_for_host_selection(dc, target, maxloop = 0, loop_delay = 1, max_age = 60)
          loop_count = 1
          until target.key?(dc) and target[dc].key?('check_time_finished')
            sleep(loop_delay)
            unless maxloop.zero?
              break if loop_count >= maxloop
              loop_count += 1
            end
          end
          return unless target[dc].key?('check_time_finished')
          loop_count = 1
          while Time.now - target[dc]['check_time_finished'] > max_age
            sleep(loop_delay)
            unless maxloop.zero?
              break if loop_count >= maxloop
              loop_count += 1
            end
          end
        end

        def select_next_host(pool_name, target, architecture = nil)
          datacenter = get_target_datacenter_from_config(pool_name)
          cluster = get_target_cluster_from_config(pool_name)
          raise("cluster for pool #{pool_name} cannot be identified") if cluster.nil?
          raise("datacenter for pool #{pool_name} cannot be identified") if datacenter.nil?
          dc = "#{datacenter}_#{cluster}"
          @provider_hosts_lock.synchronize do
            if architecture
              raise("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory") unless target[dc].key?('architectures')
              host = target[dc]['architectures'][architecture].shift
              target[dc]['architectures'][architecture] << host
              if target[dc]['hosts'].include?(host)
                target[dc]['hosts'].delete(host)
                target[dc]['hosts'] << host
              end
              return host
            else
              raise("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory") unless target[dc].key?('hosts')
              host = target[dc]['hosts'].shift
              target[dc]['hosts'] << host
              target[dc]['architectures'].each do |arch|
                if arch.include?(host)
                  target[dc]['architectures'][arch] = arch.partition { |v| v != host }.flatten
                end
              end
              return host
            end
          end
        end

        def vm_in_target?(pool_name, parent_host, architecture, target)
          datacenter = get_target_datacenter_from_config(pool_name)
          cluster = get_target_cluster_from_config(pool_name)
          raise("cluster for pool #{pool_name} cannot be identified") if cluster.nil?
          raise("datacenter for pool #{pool_name} cannot be identified") if datacenter.nil?
          dc = "#{datacenter}_#{cluster}"
          raise("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory") unless target[dc].key?('hosts')
          return true if target[dc]['architectures'][architecture].include?(parent_host)
          return false
        end

        def get_vm(_pool_name, vm_name)
          vm_hash = nil
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            vm_object = find_vm(vm_name, connection)
            return vm_hash if vm_object.nil?

            vm_folder_path = get_vm_folder_path(vm_object)
            # Find the pool name based on the folder path
            pool_name = nil
            template_name = nil
            global_config[:pools].each do |pool|
              if pool['folder'] == vm_folder_path
                pool_name = pool['name']
                template_name = pool['template']
              end
            end

            vm_hash = generate_vm_hash(vm_object, template_name, pool_name)
          end
          vm_hash
        end

        def create_vm(pool_name, new_vmname)
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?
          vm_hash = nil
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            # Assume all pool config is valid i.e. not missing
            template_path = pool['template']
            target_folder_path = pool['folder']
            target_datastore = pool['datastore']
            target_cluster_name = get_target_cluster_from_config(pool_name)
            target_datacenter_name = get_target_datacenter_from_config(pool_name)

            # Extract the template VM name from the full path
            raise("Pool #{pool_name} did specify a full path for the template for the provider #{name}") unless template_path =~ /\//
            templatefolders = template_path.split('/')
            template_name = templatefolders.pop

            # Get the actual objects from vSphere
            template_folder_object = find_folder(templatefolders.join('/'), connection, target_datacenter_name)
            raise("Pool #{pool_name} specifies a template folder of #{templatefolders.join('/')} which does not exist for the provider #{name}") if template_folder_object.nil?

            template_vm_object = template_folder_object.find(template_name)
            raise("Pool #{pool_name} specifies a template VM of #{template_name} which does not exist for the provider #{name}") if template_vm_object.nil?

            # Annotate with creation time, origin template, etc.
            # Add extraconfig options that can be queried by vmtools
            config_spec = RbVmomi::VIM.VirtualMachineConfigSpec(
              annotation: JSON.pretty_generate(
                name: new_vmname,
                created_by: provider_config['username'],
                base_template: template_path,
                creation_timestamp: Time.now.utc
              ),
              extraConfig: [
                { key: 'guestinfo.hostname', value: new_vmname }
              ]
            )

            # Put the VM in the specified folder and resource pool
            relocate_spec = RbVmomi::VIM.VirtualMachineRelocateSpec(
              datastore: find_datastore(target_datastore, connection, target_datacenter_name),
              diskMoveType: :moveChildMostDiskBacking
            )

            manage_host_selection = @config[:config]['manage_host_selection'] if @config[:config].key?('manage_host_selection')
            if manage_host_selection
              run_select_hosts(pool_name, @provider_hosts)
              target_host = select_next_host(pool_name, @provider_hosts)
              host_object = find_host_by_dnsname(connection, target_host)
              relocate_spec.host = host_object
            else
            # Choose a cluster/host to place the new VM on
              target_cluster_object = find_cluster(target_cluster_name, connection, target_datacenter_name)
              relocate_spec.pool = target_cluster_object.resourcePool
            end

            # Create a clone spec
            clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
              location: relocate_spec,
              config: config_spec,
              powerOn: true,
              template: false
            )

            begin
              vm_target_folder = find_folder(target_folder_path, connection, target_datacenter_name)
              if vm_target_folder.nil? and @config[:config].key?('create_folders') and @config[:config]['create_folders'] == true
                vm_target_folder = create_folder(connection, target_folder_path, target_datacenter_name)
              end
            rescue => _err
              if @config[:config].key?('create_folders') and @config[:config]['create_folders'] == true
                vm_target_folder = create_folder(connection, target_folder_path, target_datacenter_name)
              else
                raise(_err)
              end
            end

            # Create the new VM
            new_vm_object = template_vm_object.CloneVM_Task(
              folder: vm_target_folder,
              name: new_vmname,
              spec: clone_spec
            ).wait_for_completion

            vm_hash = generate_vm_hash(new_vm_object, template_path, pool_name)
          end
          vm_hash
        end

        def create_disk(pool_name, vm_name, disk_size)
          pool = pool_config(pool_name)
          raise("Pool #{pool_name} does not exist for the provider #{name}") if pool.nil?

          datastore_name = pool['datastore']
          raise("Pool #{pool_name} does not have a datastore defined for the provider #{name}") if datastore_name.nil?

          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            vm_object = find_vm(vm_name, connection)
            raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if vm_object.nil?

            add_disk(vm_object, disk_size, datastore_name, connection, get_target_datacenter_from_config(pool_name))
          end
          true
        end

        def create_snapshot(pool_name, vm_name, new_snapshot_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            vm_object = find_vm(vm_name, connection)
            raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if vm_object.nil?

            old_snap = find_snapshot(vm_object, new_snapshot_name)
            raise("Snapshot #{new_snapshot_name} for VM #{vm_name} in pool #{pool_name} already exists for the provider #{name}") unless old_snap.nil?

            vm_object.CreateSnapshot_Task(
              name: new_snapshot_name,
              description: 'vmpooler',
              memory: true,
              quiesce: true
            ).wait_for_completion
          end
          true
        end

        def revert_snapshot(pool_name, vm_name, snapshot_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            vm_object = find_vm(vm_name, connection)
            raise("VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if vm_object.nil?

            snapshot_object = find_snapshot(vm_object, snapshot_name)
            raise("Snapshot #{snapshot_name} for VM #{vm_name} in pool #{pool_name} does not exist for the provider #{name}") if snapshot_object.nil?

            snapshot_object.RevertToSnapshot_Task.wait_for_completion
          end
          true
        end

        def destroy_vm(_pool_name, vm_name)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            vm_object = find_vm(vm_name, connection)
            # If a VM doesn't exist then it is effectively deleted
            return true if vm_object.nil?

            # Poweroff the VM if it's running
            vm_object.PowerOffVM_Task.wait_for_completion if vm_object.runtime && vm_object.runtime.powerState && vm_object.runtime.powerState == 'poweredOn'

            # Kill it with fire
            vm_object.Destroy_Task.wait_for_completion
          end
          true
        end

        def vm_ready?(_pool_name, vm_name)
          begin
            open_socket(vm_name)
          rescue => _err
            return false
          end

          true
        end

        # VSphere Helper methods

        def get_target_cluster_from_config(pool_name)
          pool = pool_config(pool_name)
          return nil if pool.nil?

          return pool['clone_target'] unless pool['clone_target'].nil?
          return global_config[:config]['clone_target'] unless global_config[:config]['clone_target'].nil?

          nil
        end

        def get_target_datacenter_from_config(pool_name)
          pool = pool_config(pool_name)
          return nil if pool.nil?

          return pool['datacenter']            unless pool['datacenter'].nil?
          return provider_config['datacenter'] unless provider_config['datacenter'].nil?

          nil
        end

        def generate_vm_hash(vm_object, template_name, pool_name)
          hash = { 'name' => nil, 'hostname' => nil, 'template' => nil, 'poolname' => nil, 'boottime' => nil, 'powerstate' => nil }

          hash['name']     = vm_object.name
          hash['hostname'] = vm_object.summary.guest.hostName if vm_object.summary && vm_object.summary.guest && vm_object.summary.guest.hostName
          hash['template'] = template_name
          hash['poolname'] = pool_name
          hash['boottime']   = vm_object.runtime.bootTime if vm_object.runtime && vm_object.runtime.bootTime
          hash['powerstate'] = vm_object.runtime.powerState if vm_object.runtime && vm_object.runtime.powerState

          hash
        end

        # vSphere helper methods
        ADAPTER_TYPE = 'lsiLogic'.freeze
        DISK_TYPE = 'thin'.freeze
        DISK_MODE = 'persistent'.freeze

        def ensured_vsphere_connection(connection_pool_object)
          connection_pool_object[:connection] = connect_to_vsphere unless vsphere_connection_ok?(connection_pool_object[:connection])
          connection_pool_object[:connection]
        end

        def vsphere_connection_ok?(connection)
          _result = connection.serviceInstance.CurrentTime
          return true
        rescue
          return false
        end

        def connect_to_vsphere
          max_tries = global_config[:config]['max_tries'] || 3
          retry_factor = global_config[:config]['retry_factor'] || 10
          try = 1
          begin
            connection = RbVmomi::VIM.connect host: provider_config['server'],
                                              user: provider_config['username'],
                                              password: provider_config['password'],
                                              insecure: provider_config['insecure'] || true
            metrics.increment('connect.open')
            return connection
          rescue => err
            try += 1
            metrics.increment('connect.fail')
            raise err if try == max_tries
            sleep(try * retry_factor)
            retry
          end
        end

        # This should supercede the open_socket method in the Pool Manager
        def open_socket(host, domain = nil, timeout = 5, port = 22, &_block)
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

        def get_vm_folder_path(vm_object)
          # This gives an array starting from the root Datacenters folder all the way to the VM
          # [ [Object, String], [Object, String ] ... ]
          # It's then reversed so that it now goes from the VM to the Datacenter
          full_path = vm_object.path.reverse

          # Find the Datacenter object
          dc_index = full_path.index { |p| p[0].is_a?(RbVmomi::VIM::Datacenter) }
          return nil if dc_index.nil?
          # The Datacenter should be at least 2 otherwise there's something
          # wrong with the array passed in
          # This is the minimum:
          # [ VM (0), VM ROOT FOLDER (1), DC (2)]
          return nil if dc_index <= 1

          # Remove the VM name (Starting position of 1 in the slice)
          # Up until the Root VM Folder of DataCenter Node (dc_index - 2)
          full_path = full_path.slice(1..dc_index - 2)

          # Reverse the array back to normal and
          # then convert the array of paths into a '/' seperated string
          (full_path.reverse.map { |p| p[1] }).join('/')
        end

        def add_disk(vm, size, datastore, connection, datacentername)
          return false unless size.to_i > 0

          vmdk_datastore = find_datastore(datastore, connection, datacentername)
          raise("Datastore '#{datastore}' does not exist in datacenter '#{datacentername}'") if vmdk_datastore.nil?
          vmdk_file_name = "#{vm['name']}/#{vm['name']}_#{find_vmdks(vm['name'], datastore, connection, datacentername).length + 1}.vmdk"

          controller = find_disk_controller(vm)

          vmdk_spec = RbVmomi::VIM::FileBackedVirtualDiskSpec(
            capacityKb: size.to_i * 1024 * 1024,
            adapterType: ADAPTER_TYPE,
            diskType: DISK_TYPE
          )

          vmdk_backing = RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo(
            datastore: vmdk_datastore,
            diskMode: DISK_MODE,
            fileName: "[#{vmdk_datastore.name}] #{vmdk_file_name}"
          )

          device = RbVmomi::VIM::VirtualDisk(
            backing: vmdk_backing,
            capacityInKB: size.to_i * 1024 * 1024,
            controllerKey: controller.key,
            key: -1,
            unitNumber: find_disk_unit_number(vm, controller)
          )

          device_config_spec = RbVmomi::VIM::VirtualDeviceConfigSpec(
            device: device,
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation('add')
          )

          vm_config_spec = RbVmomi::VIM::VirtualMachineConfigSpec(
            deviceChange: [device_config_spec]
          )

          connection.serviceContent.virtualDiskManager.CreateVirtualDisk_Task(
            datacenter: connection.serviceInstance.find_datacenter(datacentername),
            name: "[#{vmdk_datastore.name}] #{vmdk_file_name}",
            spec: vmdk_spec
          ).wait_for_completion

          vm.ReconfigVM_Task(spec: vm_config_spec).wait_for_completion

          true
        end

        def find_datastore(datastorename, connection, datacentername)
          datacenter = connection.serviceInstance.find_datacenter(datacentername)
          raise("Datacenter #{datacentername} does not exist") if datacenter.nil?
          datacenter.find_datastore(datastorename)
        end

        def find_device(vm, device_name)
          vm.config.hardware.device.each do |device|
            return device if device.deviceInfo.label == device_name
          end

          nil
        end

        def find_disk_controller(vm)
          devices = find_disk_devices(vm)

          devices.keys.sort.each do |device|
            if devices[device]['children'].length < 15
              return find_device(vm, devices[device]['device'].deviceInfo.label)
            end
          end

          nil
        end

        def find_disk_devices(vm)
          devices = {}

          vm.config.hardware.device.each do |device|
            if device.is_a? RbVmomi::VIM::VirtualSCSIController
              if devices[device.controllerKey].nil?
                devices[device.key] = {}
                devices[device.key]['children'] = []
              end

              devices[device.key]['device'] = device
            end

            if device.is_a? RbVmomi::VIM::VirtualDisk
              if devices[device.controllerKey].nil?
                devices[device.controllerKey] = {}
                devices[device.controllerKey]['children'] = []
              end

              devices[device.controllerKey]['children'].push(device)
            end
          end

          devices
        end

        def find_disk_unit_number(vm, controller)
          used_unit_numbers = []
          available_unit_numbers = []

          devices = find_disk_devices(vm)

          devices.keys.sort.each do |c|
            next unless controller.key == devices[c]['device'].key
            used_unit_numbers.push(devices[c]['device'].scsiCtlrUnitNumber)
            devices[c]['children'].each do |disk|
              used_unit_numbers.push(disk.unitNumber)
            end
          end

          (0..15).each do |scsi_id|
            if used_unit_numbers.grep(scsi_id).length <= 0
              available_unit_numbers.push(scsi_id)
            end
          end

          available_unit_numbers.sort[0]
        end

        # Finds the first reference to and returns the folder object for a foldername and an optional datacenter
        # Params:
        # +foldername+:: the folder to find (optionally with / in which case the foldername will be split and each element searched for)
        # +connection+:: the vsphere connection object
        # +datacentername+:: the datacenter where the folder resides, or nil to return the first datacenter found
        # returns a ManagedObjectReference for the first folder found or nil if none found
        def find_folder(foldername, connection, datacentername)
          datacenter = connection.serviceInstance.find_datacenter(datacentername)
          raise("Datacenter #{datacentername} does not exist") if datacenter.nil?
          base = datacenter.vmFolder

          folders = foldername.split('/')
          folders.each do |folder|
            raise("Unexpected object type encountered (#{base.class}) while finding folder") unless base.is_a? RbVmomi::VIM::Folder
            base = base.childEntity.find { |f| f.name == folder }
          end

          base
        end

        # Returns an array containing cumulative CPU and memory utilization of a host, and its object reference
        # Params:
        # +model+:: CPU arch version to match on
        # +limit+:: Hard limit for CPU or memory utilization beyond which a host is excluded for deployments
        # returns nil if one on these conditions is true:
        #    the model param is defined and cannot be found
        #    the host is in maintenance mode
        #    the host status is not 'green'
        #    the cpu or memory utilization is bigger than the limit param
        def get_host_utilization(host, model = nil, limit = 90)
          limit = @config[:config]['utilization_limit'] if @config[:config].key?('utilization_limit')
          if model
            return nil unless host_has_cpu_model?(host, model)
          end
          return nil if host.runtime.inMaintenanceMode
          return nil unless host.overallStatus == 'green'
          return nil unless host.configIssue.empty?

          cpu_utilization = cpu_utilization_for host
          memory_utilization = memory_utilization_for host

          return nil if cpu_utilization == 0
          return nil if memory_utilization == 0
          return nil if cpu_utilization > limit
          return nil if memory_utilization > limit

          [cpu_utilization, host]
        end

        def host_has_cpu_model?(host, model)
          get_host_cpu_arch_version(host) == model
        end

        def get_host_cpu_arch_version(host)
          cpu_model = host.hardware.cpuPkg[0].description
          cpu_model_parts = cpu_model.split
          arch_version = cpu_model_parts[4]
          arch_version
        end

        def cpu_utilization_for(host)
          cpu_usage = host.summary.quickStats.overallCpuUsage
          cpu_size = host.summary.hardware.cpuMhz * host.summary.hardware.numCpuCores
          (cpu_usage.to_f / cpu_size.to_f) * 100
        end

        def memory_utilization_for(host)
          memory_usage = host.summary.quickStats.overallMemoryUsage
          memory_size = host.summary.hardware.memorySize / 1024 / 1024
          (memory_usage.to_f / memory_size.to_f) * 100
        end

        def get_average_cluster_utilization(hosts)
          utilization_counts = hosts.map { |host| host[0] }
          utilization_counts.inject(:+) / hosts.count
        end

        def build_compatible_hosts_lists(hosts, percentage)
          hosts_with_arch_versions = hosts.map { |h|
            {
            'utilization' => h[0],
            'host_object' => h[1],
            'architecture' => get_host_cpu_arch_version(h[1])
            }
          }
          versions = hosts_with_arch_versions.map { |host| host['architecture'] }.uniq
          architectures = {}
          versions.each do |version|
            architectures[version] = []
          end

          hosts_with_arch_versions.each do |h|
            architectures[h['architecture']] << [h['utilization'], h['host_object'], h['architecture']]
          end

          versions.each do |version|
            targets = []
            targets = select_least_used_hosts(architectures[version], percentage)
            architectures[version] = targets
          end
          architectures
        end

        def select_least_used_hosts(hosts, percentage)
          raise('Provided hosts list to select_least_used_hosts is empty') if hosts.empty?
          average_utilization = get_average_cluster_utilization(hosts)
          least_used_hosts = []
          hosts.each do |host|
            least_used_hosts << host if host[0] <= average_utilization
          end
          hosts_to_select = (hosts.count * (percentage  / 100.0)).to_int
          hosts_to_select = hosts.count - 1 if percentage == 100
          least_used_hosts.sort[0..hosts_to_select].map { |host| host[1].name }
        end

        def find_least_used_hosts(cluster, datacentername, percentage)
          @connection_pool.with_metrics do |pool_object|
            connection = ensured_vsphere_connection(pool_object)
            cluster_object = find_cluster(cluster, connection, datacentername)
            raise("Cluster #{cluster} cannot be found") if cluster_object.nil?
            target_hosts = get_cluster_host_utilization(cluster_object)
            raise("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory'") if target_hosts.empty?
            architectures = build_compatible_hosts_lists(target_hosts, percentage)
            least_used_hosts = select_least_used_hosts(target_hosts, percentage)
            {
              'hosts' => least_used_hosts,
              'architectures' => architectures
            }
          end
        end

        def find_host_by_dnsname(connection, dnsname)
          host_object = connection.searchIndex.FindByDnsName(dnsName: dnsname, vmSearch: false)
          return nil if host_object.nil?
          host_object
        end

        def find_least_used_host(cluster, connection, datacentername)
          cluster_object = find_cluster(cluster, connection, datacentername)
          target_hosts = get_cluster_host_utilization(cluster_object)
          raise("There is no host candidate in vcenter that meets all the required conditions, check that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory'") if target_hosts.empty?
          least_used_host = target_hosts.sort[0][1]
          least_used_host
        end

        def find_cluster(cluster, connection, datacentername)
          datacenter = connection.serviceInstance.find_datacenter(datacentername)
          raise("Datacenter #{datacentername} does not exist") if datacenter.nil?
          datacenter.hostFolder.children.find { |cluster_object| cluster_object.name == cluster }
        end

        def get_cluster_host_utilization(cluster, model = nil)
          cluster_hosts = []
          cluster.host.each do |host|
            host_usage = get_host_utilization(host, model)
            cluster_hosts << host_usage if host_usage
          end
          cluster_hosts
        end

        def find_least_used_vpshere_compatible_host(vm)
          source_host = vm.summary.runtime.host
          model = get_host_cpu_arch_version(source_host)
          cluster = source_host.parent
          target_hosts = get_cluster_host_utilization(cluster, model)
          raise("There is no host candidate in vcenter that meets all the required conditions, check that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory'") if target_hosts.empty?
          target_host = target_hosts.sort[0][1]
          [target_host, target_host.name]
        end

        def find_pool(poolname, connection, datacentername)
          datacenter = connection.serviceInstance.find_datacenter(datacentername)
          raise("Datacenter #{datacentername} does not exist") if datacenter.nil?
          base = datacenter.hostFolder
          pools = poolname.split('/')
          pools.each do |pool|
            if base.is_a?(RbVmomi::VIM::Folder)
              base = base.childEntity.find { |f| f.name == pool }
            elsif base.is_a?(RbVmomi::VIM::ClusterComputeResource)
              base = base.resourcePool.resourcePool.find { |f| f.name == pool }
            elsif base.is_a?(RbVmomi::VIM::ResourcePool)
              base = base.resourcePool.find { |f| f.name == pool }
            else
              raise("Unexpected object type encountered (#{base.class}) while finding resource pool")
            end
          end

          base = base.resourcePool unless base.is_a?(RbVmomi::VIM::ResourcePool) && base.respond_to?(:resourcePool)
          base
        end

        def find_snapshot(vm, snapshotname)
          get_snapshot_list(vm.snapshot.rootSnapshotList, snapshotname) if vm.snapshot
        end

        def find_vm(vmname, connection)
          find_vm_light(vmname, connection) || find_vm_heavy(vmname, connection)[vmname]
        end

        def find_vm_light(vmname, connection)
          connection.searchIndex.FindByDnsName(vmSearch: true, dnsName: vmname)
        end

        def find_vm_heavy(vmname, connection)
          vmname = vmname.is_a?(Array) ? vmname : [vmname]
          container_view = get_base_vm_container_from(connection)
          property_collector = connection.propertyCollector

          object_set = [{
            obj: container_view,
            skip: true,
            selectSet: [RbVmomi::VIM::TraversalSpec.new(
              name: 'gettingTheVMs',
              path: 'view',
              skip: false,
              type: 'ContainerView'
            )]
          }]

          prop_set = [{
            pathSet: ['name'],
            type: 'VirtualMachine'
          }]

          results = property_collector.RetrievePropertiesEx(
            specSet: [{
              objectSet: object_set,
              propSet: prop_set
            }],
            options: { maxObjects: nil }
          )

          vms = {}
          results.objects.each do |result|
            name = result.propSet.first.val
            next unless vmname.include? name
            vms[name] = result.obj
          end

          while results.token
            results = property_collector.ContinueRetrievePropertiesEx(token: results.token)
            results.objects.each do |result|
              name = result.propSet.first.val
              next unless vmname.include? name
              vms[name] = result.obj
            end
          end

          vms
        end

        def find_vmdks(vmname, datastore, connection, datacentername)
          disks = []

          vmdk_datastore = find_datastore(datastore, connection, datacentername)

          vm_files = connection.serviceContent.propertyCollector.collectMultiple vmdk_datastore.vm, 'layoutEx.file'
          vm_files.keys.each do |f|
            vm_files[f]['layoutEx.file'].each do |l|
              if l.name =~ /^\[#{vmdk_datastore.name}\] #{vmname}\/#{vmname}_([0-9]+).vmdk/
                disks.push(l)
              end
            end
          end

          disks
        end

        def get_base_vm_container_from(connection)
          view_manager = connection.serviceContent.viewManager
          view_manager.CreateContainerView(
            container: connection.serviceContent.rootFolder,
            recursive: true,
            type: ['VirtualMachine']
          )
        end

        def get_snapshot_list(tree, snapshotname)
          snapshot = nil

          tree.each do |child|
            if child.name == snapshotname
              snapshot ||= child.snapshot
            else
              snapshot ||= get_snapshot_list(child.childSnapshotList, snapshotname)
            end
          end

          snapshot
        end

        def get_vm_details(vm_name, connection)
          vm_object = find_vm(vm_name, connection)
          return nil if vm_object.nil?
          parent_host_object = vm_object.summary.runtime.host if vm_object.summary && vm_object.summary.runtime && vm_object.summary.runtime.host
          parent_host = parent_host_object.name
          raise('Unable to determine which host the VM is running on') if parent_host.nil?
          architecture = get_host_cpu_arch_version(parent_host_object)
          {
            'host_name' => parent_host,
            'object' => vm_object,
            'architecture' => architecture
          }
        end

        def migration_enabled?(config)
          migration_limit = config[:config]['migration_limit']
          return false unless migration_limit.is_a? Integer
          return true if migration_limit > 0
          false
        end

        def migrate_vm(pool_name, vm_name)
          @connection_pool.with_metrics do |pool_object|
            begin
              connection = ensured_vsphere_connection(pool_object)
              vm_hash = get_vm_details(vm_name, connection)
              migration_limit = @config[:config]['migration_limit'] if @config[:config].key?('migration_limit')
              migration_count = $redis.scard('vmpooler__migration')
              if migration_enabled? @config
                if migration_count >= migration_limit
                  logger.log('s', "[ ] [#{pool_name}] '#{vm_name}' is running on #{vm_hash['host_name']}. No migration will be evaluated since the migration_limit has been reached")
                  return
                end
                run_select_hosts(pool_name, @provider_hosts)
                if vm_in_target?(pool_name, vm_hash['host_name'], vm_hash['architecture'], @provider_hosts)
                  logger.log('s', "[ ] [#{pool_name}] No migration required for '#{vm_name}' running on #{vm_hash['host_name']}")
                else
                  migrate_vm_to_new_host(pool_name, vm_name, vm_hash, connection)
                end
              else
                logger.log('s', "[ ] [#{pool_name}] '#{vm_name}' is running on #{vm_hash['host_name']}")
              end
            rescue => _err
              logger.log('s', "[!] [#{pool_name}] '#{vm_name}' is running on #{vm_hash['host_name']}")
              raise _err
            end
          end
        end

        def migrate_vm_to_new_host(pool_name, vm_name, vm_hash, connection)
          $redis.sadd('vmpooler__migration', vm_name)
          target_host_name = select_next_host(pool_name, @provider_hosts, vm_hash['architecture'])
          target_host_object = find_host_by_dnsname(connection, target_host_name)
          finish = migrate_vm_and_record_timing(pool_name, vm_name, vm_hash, target_host_object, target_host_name)
          #logger.log('s', "Provider_hosts is: #{provider.provider_hosts}")
          logger.log('s', "[>] [#{pool_name}] '#{vm_name}' migrated from #{vm_hash['host_name']} to #{target_host_name} in #{finish} seconds")
        ensure
          $redis.srem('vmpooler__migration', vm_name)
        end

        def migrate_vm_and_record_timing(pool_name, vm_name, vm_hash, target_host_object, dest_host_name)
          start = Time.now
          migrate_vm_host(vm_hash['object'], target_host_object)
          finish = format('%.2f', Time.now - start)
          metrics.timing("migrate.#{pool_name}", finish)
          metrics.increment("migrate_from.#{vm_hash['host_name']}")
          metrics.increment("migrate_to.#{dest_host_name}")
          checkout_to_migration = format('%.2f', Time.now - Time.parse($redis.hget("vmpooler__vm__#{vm_name}", 'checkout')))
          $redis.hset("vmpooler__vm__#{vm_name}", 'migration_time', finish)
          $redis.hset("vmpooler__vm__#{vm_name}", 'checkout_to_migration', checkout_to_migration)
          finish
        end

        def migrate_vm_host(vm_object, host)
          relospec = RbVmomi::VIM.VirtualMachineRelocateSpec(host: host)
          vm_object.RelocateVM_Task(spec: relospec).wait_for_completion
        end

        def create_folder(connection, new_folder, datacenter)
          dc = connection.serviceInstance.find_datacenter(datacenter)
          folder_object = dc.vmFolder.traverse(new_folder, type=RbVmomi::VIM::Folder, create=true)
          raise("Cannot create folder #{new_folder}") if folder_object.nil?
          folder_object
        end
      end
    end
  end
end
