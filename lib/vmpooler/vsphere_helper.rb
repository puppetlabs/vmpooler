require 'rubygems' unless defined?(Gem)

module Vmpooler
  class VsphereHelper
    ADAPTER_TYPE = 'lsiLogic'
    DISK_TYPE = 'thin'
    DISK_MODE = 'persistent'

    def initialize(credentials, metrics)
      $credentials = credentials
      $metrics = metrics
    end

    def ensure_connected(connection, credentials)
      connection.serviceInstance.CurrentTime
    rescue
      $metrics.increment("connect.open")
      connect_to_vsphere $credentials
    end

    def connect_to_vsphere(credentials)
      @connection = RbVmomi::VIM.connect host: credentials['server'],
                                         user: credentials['username'],
                                         password: credentials['password'],
                                         insecure: credentials['insecure'] || true
    end

    def add_disk(vm, size, datastore)
      ensure_connected @connection, $credentials

      return false unless size.to_i > 0

      vmdk_datastore = find_datastore(datastore)
      vmdk_file_name = "#{vm['name']}/#{vm['name']}_#{find_vmdks(vm['name'], datastore).length + 1}.vmdk"

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

      @connection.serviceContent.virtualDiskManager.CreateVirtualDisk_Task(
        datacenter: @connection.serviceInstance.find_datacenter,
        name: "[#{vmdk_datastore.name}] #{vmdk_file_name}",
        spec: vmdk_spec
      ).wait_for_completion

      vm.ReconfigVM_Task(spec: vm_config_spec).wait_for_completion

      true
    end

    def find_datastore(datastorename)
      ensure_connected @connection, $credentials

      datacenter = @connection.serviceInstance.find_datacenter
      datacenter.find_datastore(datastorename)
    end

    def find_device(vm, deviceName)
      ensure_connected @connection, $credentials

      vm.config.hardware.device.each do |device|
        return device if device.deviceInfo.label == deviceName
      end

      nil
    end

    def find_disk_controller(vm)
      ensure_connected @connection, $credentials

      devices = find_disk_devices(vm)

      devices.keys.sort.each do |device|
        if devices[device]['children'].length < 15
          return find_device(vm, devices[device]['device'].deviceInfo.label)
        end
      end

      nil
    end

    def find_disk_devices(vm)
      ensure_connected @connection, $credentials

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
      ensure_connected @connection, $credentials

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

    def find_folder(foldername)
      ensure_connected @connection, $credentials

      datacenter = @connection.serviceInstance.find_datacenter
      base = datacenter.vmFolder
      folders = foldername.split('/')
      folders.each do |folder|
        case base
          when RbVmomi::VIM::Folder
            base = base.childEntity.find { |f| f.name == folder }
          else
            abort "Unexpected object type encountered (#{base.class}) while finding folder"
        end
      end

      base
    end

    # Returns an array containing cumulative CPU and memory utilization of a host, and its object reference
    # Params:
    # +model+:: CPU arch version to match on
    # +limit+:: Hard limit for CPU or memory utilization beyond which a host is excluded for deployments
    def get_host_utilization(host, model=nil, limit=90)
      if model
        return nil unless host_has_cpu_model? host, model
      end
      return nil if host.runtime.inMaintenanceMode
      return nil unless host.overallStatus == 'green'

      cpu_utilization = cpu_utilization_for host
      memory_utilization = memory_utilization_for host

      return nil if cpu_utilization > limit
      return nil if memory_utilization > limit

      [ cpu_utilization + memory_utilization, host ]
    end

    def host_has_cpu_model?(host, model)
       get_host_cpu_arch_version(host) == model
    end

    def get_host_cpu_arch_version(host)
      cpu_model = host.hardware.cpuPkg[0].description
      cpu_model_parts = cpu_model.split()
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

    def find_least_used_host(cluster)
      ensure_connected @connection, $credentials

      cluster_object = find_cluster(cluster)
      target_hosts = get_cluster_host_utilization(cluster_object)
      least_used_host = target_hosts.sort[0][1]
      least_used_host
    end

    def find_cluster(cluster)
      datacenter = @connection.serviceInstance.find_datacenter
      datacenter.hostFolder.children.find { |cluster_object| cluster_object.name == cluster }
    end

    def get_cluster_host_utilization(cluster)
      cluster_hosts = []
      cluster.host.each do |host|
        host_usage = get_host_utilization(host)
        cluster_hosts << host_usage if host_usage
      end
      cluster_hosts
    end

    def find_least_used_compatible_host(vm)
      ensure_connected @connection, $credentials

      source_host = vm.summary.runtime.host
      model = get_host_cpu_arch_version(source_host)
      cluster = source_host.parent
      target_hosts = []
      cluster.host.each do |host|
        host_usage = get_host_utilization(host, model)
        target_hosts << host_usage if host_usage
      end
      target_host = target_hosts.sort[0][1]
      [target_host, target_host.name]
    end

    def find_pool(poolname)
      ensure_connected @connection, $credentials

      datacenter = @connection.serviceInstance.find_datacenter
      base = datacenter.hostFolder
      pools = poolname.split('/')
      pools.each do |pool|
        case base
          when RbVmomi::VIM::Folder
            base = base.childEntity.find { |f| f.name == pool }
          when RbVmomi::VIM::ClusterComputeResource
            base = base.resourcePool.resourcePool.find { |f| f.name == pool }
          when RbVmomi::VIM::ResourcePool
            base = base.resourcePool.find { |f| f.name == pool }
          else
            abort "Unexpected object type encountered (#{base.class}) while finding resource pool"
        end
      end

      base = base.resourcePool unless base.is_a?(RbVmomi::VIM::ResourcePool) && base.respond_to?(:resourcePool)
      base
    end

    def find_snapshot(vm, snapshotname)
      if vm.snapshot
        get_snapshot_list(vm.snapshot.rootSnapshotList, snapshotname)
      end
    end

    def find_vm(vmname)
      ensure_connected @connection, $credentials
      find_vm_light(vmname) || find_vm_heavy(vmname)[vmname]
    end

    def find_vm_light(vmname)
      ensure_connected @connection, $credentials

      @connection.searchIndex.FindByDnsName(vmSearch: true, dnsName: vmname)
    end

    def find_vm_heavy(vmname)
      ensure_connected @connection, $credentials

      vmname = vmname.is_a?(Array) ? vmname : [vmname]
      containerView = get_base_vm_container_from @connection
      propertyCollector = @connection.propertyCollector

      objectSet = [{
        obj: containerView,
        skip: true,
        selectSet: [RbVmomi::VIM::TraversalSpec.new(
            name: 'gettingTheVMs',
            path: 'view',
            skip: false,
            type: 'ContainerView'
        )]
      }]

      propSet = [{
        pathSet: ['name'],
        type: 'VirtualMachine'
      }]

      results = propertyCollector.RetrievePropertiesEx(
        specSet: [{
          objectSet: objectSet,
          propSet: propSet
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
        results = propertyCollector.ContinueRetrievePropertiesEx(token: results.token)
        results.objects.each do |result|
          name = result.propSet.first.val
          next unless vmname.include? name
          vms[name] = result.obj
        end
      end

      vms
    end

    def find_vmdks(vmname, datastore)
      ensure_connected @connection, $credentials

      disks = []

      vmdk_datastore = find_datastore(datastore)

      vm_files = vmdk_datastore._connection.serviceContent.propertyCollector.collectMultiple vmdk_datastore.vm, 'layoutEx.file'
      vm_files.keys.each do |f|
        vm_files[f]['layoutEx.file'].each do |l|
          if l.name.match(/^\[#{vmdk_datastore.name}\] #{vmname}\/#{vmname}_([0-9]+).vmdk/)
            disks.push(l)
          end
        end
      end

      disks
    end

    def get_base_vm_container_from(connection)
      ensure_connected @connection, $credentials

      viewManager = connection.serviceContent.viewManager
      viewManager.CreateContainerView(
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

    def migrate_vm_host(vm, host)
      relospec = RbVmomi::VIM.VirtualMachineRelocateSpec(host: host)
      vm.RelocateVM_Task(spec: relospec).wait_for_completion
    end

    def close
      @connection.close
    end
  end
end
