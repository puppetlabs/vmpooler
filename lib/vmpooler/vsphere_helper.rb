require 'rubygems' unless defined?(Gem)

module Vmpooler
  class VsphereHelper
    def initialize(_vInfo = {})
      config_file = File.expand_path('vmpooler.yaml')
      vsphere = YAML.load_file(config_file)[:vsphere]

      @connection = RbVmomi::VIM.connect host: vsphere['server'],
                                         user: vsphere['username'],
                                         password: vsphere['password'],
                                         insecure: true
    end

    def find_datastore(datastorename)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

      datacenter = @connection.serviceInstance.find_datacenter
      datacenter.find_datastore(datastorename)
    end

    def find_folder(foldername)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

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

    def find_least_used_host(cluster)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

      hosts = {}
      hosts_sort = {}

      datacenter = @connection.serviceInstance.find_datacenter
      datacenter.hostFolder.children.each do |folder|
        next unless folder.name == cluster
        folder.host.each do |host|
          if
            (host.overallStatus == 'green') &&
            (!host.runtime.inMaintenanceMode)

            hosts[host.name] = host
            hosts_sort[host.name] = host.vm.length
          end
        end
      end

      hosts[hosts_sort.sort_by { |_k, v| v }[0][0]]
    end

    def find_pool(poolname)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

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
      else
        return []
      end
    end

    def find_vm(vmname)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

      @connection.searchIndex.FindByDnsName(vmSearch: true, dnsName: vmname)
    end

    def find_vm_heavy(vmname)
      begin
        @connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

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

    def get_base_vm_container_from(connection)
      begin
        connection.serviceInstance.CurrentTime
      rescue
        initialize
      end

      viewManager = connection.serviceContent.viewManager
      viewManager.CreateContainerView(
        container: connection.serviceContent.rootFolder,
        recursive: true,
        type: ['VirtualMachine']
      )
    end

    def get_snapshot_list(tree, snapshotname)
      snapshot = []

      tree.each do |child|
        if child.name == snapshotname
          snapshot ||= child.snapshot
        else
          snapshot ||= get_snapshot_list(child.childSnapshotList, snapshotname)
        end
      end

      snapshot
    end

    def close
      @connection.close
    end
  end
end
