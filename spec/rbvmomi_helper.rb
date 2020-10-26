# -----------------------------------------------------------------------------------------------------------------
# Managed Objects (https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/index-mo_types.html)
# -----------------------------------------------------------------------------------------------------------------

MockClusterComputeResource = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ClusterComputeResource.html
  # From MockClusterComputeResource
  :actionHistory, :configuration, :drsFault, :drsRecommendation, :migrationHistory, :recommendation,
  # From ComputeResource
  :resourcePool,
  # From ManagedEntity
  :name
)

MockComputeResource = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.ComputeResource.html
  # From ComputeResource
  :configurationEx, :datastore, :host, :network, :resourcePool, :summary,
  # From ManagedEntity
  :name
)

MockContainerView = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.view.ContainerView.html
  # From ContainerView
  :container, :recursive, :type
) do
  def _search_tree(layer)
    results = []

    layer.children.each do |child|
      if type.any? { |t| child.is_a?(RbVmomi::VIM.const_get(t)) }
        results << child
      end

      if recursive && child.respond_to?(:children)
          results += _search_tree(child)
      end
    end
    results
  end

  def view
    _search_tree(container)
  end

  def DestroyView
  end
end

MockDatacenter = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Datacenter.html
  # From Datacenter
  :datastore, :datastoreFolder, :hostFolder, :network, :networkFolder, :vmFolder,
  # From ManagedEntity
  :name
) do
  # From RBVMOMI::VIM::Datacenter https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/Datacenter.rb

  # Find the Datastore with the given +name+.
  def find_datastore name
    datastore.find { |x| x.name == name }
  end
end

MockNetwork = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Network.html
  # From Network
  :host, :name, :summary, :vm
)

MockVirtualVmxnet3 = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualVmxnet.html
  # From VirtualEthenetCard
  :addressType,
  # From VirtualDevice
  :key, :deviceInfo, :backing, :connectable
)

MockDatastore = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Datastore.html
  # From Datastore
  :browser, :capability, :host, :info, :iormConfiguration, :summary, :vm,
  # From ManagedEntity
  :name
)

MockFolder = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Folder.html
  # From Folder
  :childEntity, :childType,
  # From ManagedEntity
  :name
) do
  # From RBVMOMI::VIM::Folder https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/Folder.rb#L107-L110
  def children
    childEntity
  end

  # https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/Folder.rb#L9-L12
  def find(name, type=Object)
    # Fake the searchIndex
    childEntity.each do |child|
      if child.name == name
        if child.kind_of?(type)
          return child
        else
          return nil
        end
      end
    end

    nil
  end
end

MockHostSystem = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.HostSystem.html
  # From HostSystem
  :capability, :config, :configManager, :datastore, :datastoreBrowser, :hardware, :network, :runtime, :summary, :systemResources, :vm,
  # From ManagedEntity
  :overallStatus, :name, :parent,
  # From ManagedObject
  :configIssue
)

MockPropertyCollector = Struct.new(
  # https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.query.PropertyCollector.html
  # PropertyCollector
  :filter
)

MockResourcePool = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ResourcePool.html
  # From ResourcePool
  :childConfiguration, :config, :owner, :resourcePool, :runtime, :summary, :vm,
  # From ManagedEntity
  :name
)

MockSearchIndex = Object
# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.SearchIndex.html

MockServiceInstance = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.ServiceInstance.html
  # From ServiceInstance
  :capability, :content, :serverClock
) do
  # From ServiceInstance 
  # Mock the CurrentTime method so that it appears the ServiceInstance is valid.
  def CurrentTime
    Time.now
  end

  # From RBVMOMI::VIM::ServiceInstance https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/ServiceInstance.rb
  def find_datacenter(path=nil)
    # In our mocked instance, DataCenters are always in the root Folder.
    # If path is nil the first DC is returned otherwise match by name
    content.rootFolder.childEntity.each do |child|
      if child.is_a?(RbVmomi::VIM::Datacenter)
        return child if path.nil? || child.name == path
      end
    end
    nil
  end
end

MockTask = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.Task.html
  # From Task
  :info,
) do
  # From RBVMOMI https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/Task.rb
  # Mock the with 'Not Implemented'
  def wait_for_completion
    raise(RuntimeError,'Not Implemented')
  end
end

MockViewManager = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.view.ViewManager.html
  # From ViewManager
  :viewList,
) do
  # From ViewManager 
  def CreateContainerView(options)
    mock_RbVmomi_VIM_ContainerView({
      :container => options[:container],
      :recursive => options[:recursive],
      :type => options[:type],
    })
  end
end

MockVirtualDiskManager = Object
# https://pubs.vmware.com/vsphere-55/index.jsp#com.vmware.wssdk.apiref.doc/vim.VirtualDiskManager.html

MockVirtualMachine = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.VirtualMachine.html
  # From VirtualMachine
  :config, :runtime, :snapshot, :summary,
  # From ManagedEntity
  :name,
  # From RbVmomi::VIM::ManagedEntity
  # https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim/ManagedEntity.rb
  :path
)

MockVirtualMachineSnapshot = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.Snapshot.html
  # From VirtualMachineSnapshot
  :config
)

# -------------------------------------------------------------------------------------------------------------
# Data Objects (https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/index-do_types.html)
# -------------------------------------------------------------------------------------------------------------

MockDescription = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.Description.html
  # From Description
  :label, :summary
)

MockVirtualEthernetCardNetworkBackingInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualEthernetCard.NetworkBackingInfo.html
  # From VirtualEthernetCardNetworkBackingInfo
  :network,

  # From VirtualDeviceBackingInfo
  :deviceName, :useAutoDetect
)

MockVirtualDeviceConnectInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualDevice.ConnectInfo.html
  # From VirtualDeviceConnectInfo
  :allowGuestControl, :connected, :startConnected
)

MockVirtualMachineConfigSpec = Struct.new(
  # https://pubs.vmware.com/vi3/sdk/ReferenceGuide/vim.vm.ConfigSpec.html
  # From VirtualMachineConfigSpec
  :deviceChange, :annotation, :extraConfig
)

MockVirtualMachineRelocateSpec = Struct.new(
  # https://pubs.vmware.com/vi3/sdk/ReferenceGuide/vim.vm.RelocateSpec.html
  # From VirtualMachineRelocateSpec
  :datastore, :diskMoveType, :pool
)

MockDynamicProperty = Struct.new(
  # https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.DynamicProperty.html
  # From DynamicProperty
  :name, :val
)

MockHostCpuPackage = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.CpuPackage.html
  # From HostCpuPackage
  :busHz, :cpuFeature, :description, :hz, :index, :threadId, :vendor
)

MockHostHardwareSummary = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.Summary.HardwareSummary.html
  # From HostHardwareSummary
  :cpuMhz, :numCpuCores, :numCpuPkgs, :memorySize
)

MockHostListSummary = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.Summary.html
  # From HostListSummary
  :quickStats, :hardware
)

MockHostListSummaryQuickStats = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.Summary.QuickStats.html
  # From HostListSummaryQuickStats
  :overallCpuUsage, :overallMemoryUsage
)

MockHostRuntimeInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.RuntimeInfo.html
  # From HostRuntimeInfo
  :bootTime, :connectionState, :healthSystemRuntime, :inMaintenanceMode, :powerState, :tpmPcrValues
)

MockHostSystemHostHardwareInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.host.HardwareInfo.html
  # From HostHardwareInfo
  :biosInfo, :cpuFeature, :cpuInfo, :cpuPkg, :cpuPowerManagementInfo, :memorySize, :numaInfo, :pciDevice, :systemInfo
)

MockObjectContent = Struct.new(
  # https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.query.PropertyCollector.ObjectContent.html
  # From ObjectContent
  :missingSet, :obj, :propSet
)

MockRetrieveResult = Struct.new(
  # https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.query.PropertyCollector.RetrieveResult.html
  # From RetrieveResult
  :objects, :token
)

MockServiceContent = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ServiceInstanceContent.html#field_detail
  # From ServiceContent
  :propertyCollector, :rootFolder, :searchIndex, :viewManager, :virtualDiskManager
)

MockVirtualDevice = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualDevice.html
  # From VirtualDevice
  :deviceInfo, :controllerKey, :key, :backing, :connectable, :unitNumber
)

MockVirtualDisk = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualDisk.html
  # From VirtualDisk
  :capacityInKB, :shares,
  # From VirtualDevice
  :deviceInfo, :controllerKey, :key, :backing, :connectable, :unitNumber
)

MockVirtualHardware = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.VirtualHardware.html
  # From VirtualHardware
  :device
)

MockVirtualMachineConfigInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.ConfigInfo.html
  # From VirtualMachineConfigInfo
  :hardware
)

MockVirtualMachineFileLayoutExFileInfo = Struct.new(
  # https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvim.vm.FileLayoutEx.FileInfo.html
  # From VirtualMachineFileLayoutExFileInfo
  :key, :name, :size, :type, :uniqueSize
)

MockVirtualMachineGuestSummary = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.Summary.GuestSummary.html
  # From VirtualMachineGuestSummary
  :hostName
)

MockVirtualMachineRuntimeInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.RuntimeInfo.html
  # From VirtualMachineRuntimeInfo
  :bootTime, :cleanPowerOff, :connectionState, :faultToleranceState, :host, :maxCpuUsage, :maxMemoryUsage, :memoryOverhead,
  :needSecondaryReason, :numMksConnections, :powerState, :question, :recordReplayState, :suspendInterval, :suspendTime, :toolsInstallerMounted
)

MockVirtualMachineSnapshotInfo = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.SnapshotInfo.html
  # From MockVirtualMachineSnapshotInfo
  :currentSnapshot, :rootSnapshotList
)

MockVirtualMachineSnapshotTree = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.SnapshotTree.html
  # From VirtualMachineSnapshotTree
  :backupManifest, :childSnapshotList, :createTime, :description, :id, :name, :quiesced, :replaySupported,
  :snapshot, :state, :vm
)

MockVirtualMachineSummary = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.Summary.html
  # From VirtualMachineSummary
  :config, :customValue, :guest, :quickStats, :runtime, :storage, :vm
)

MockVirtualSCSIController = Struct.new(
  # https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualSCSIController.html
  # From VirtualSCSIController
  :hotAddRemove, :scsiCtlrUnitNumber, :sharedBus,
  # From VirtualDevice
  :deviceInfo, :controllerKey, :key, :backing, :connectable, :unitNumber
)

# --------------------
# RBVMOMI only Objects
# --------------------
MockRbVmomiVIMConnection = Struct.new(
  # https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim.rb
  :serviceInstance, :serviceContent, :rootFolder, :root
) do
  # From https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim.rb
  # Alias to serviceContent.searchIndex
  def searchIndex
    serviceContent.searchIndex
  end
  # Alias to serviceContent.propertyCollector
  def propertyCollector
    serviceContent.propertyCollector
  end
end

# -------------------------------------------------------------------------------------------------------------
# Mocking Methods
# -------------------------------------------------------------------------------------------------------------

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ClusterComputeResource.html
def mock_RbVmomi_VIM_ClusterComputeResource(options = {})
  options[:name]  = 'Cluster' + rand(65536).to_s if options[:name].nil?

  mock = MockClusterComputeResource.new()

  mock.name = options[:name]
  # All cluster compute resources have a root Resource Pool
  mock.resourcePool = mock_RbVmomi_VIM_ResourcePool({:name => options[:name]})

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::ClusterComputeResource
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.view.ContainerView.html
def mock_RbVmomi_VIM_ContainerView(options = {})
  mock = MockContainerView.new()
  mock.container = options[:container]
  mock.recursive = options[:recursive]
  mock.type = options[:type]

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.ComputeResource.html
def mock_RbVmomi_VIM_ComputeResource(options = {})
  options[:name]  = 'Compute' + rand(65536).to_s if options[:name].nil?
  options[:hosts] = [{}] if options[:hosts].nil?

  mock = MockComputeResource.new()

  mock.name = options[:name]
  mock.host = []

  # A compute resource must have at least one host.
  options[:hosts].each do |host_options|
    mock_host = mock_RbVmomi_VIM_HostSystem(host_options)
    mock_host.parent = mock
    mock.host << mock_host
  end

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::ComputeResource
  end

  mock
end

# https://github.com/vmware/rbvmomi/blob/master/lib/rbvmomi/vim.rb
def mock_RbVmomi_VIM_Connection(options = {})
  options[:serviceInstance] = {} if options[:serviceInstance].nil?
  options[:serviceContent]  = {} if options[:serviceContent].nil?

  mock = MockRbVmomiVIMConnection.new()
  mock.serviceContent = mock_RbVmomi_VIM_ServiceContent(options[:serviceContent])
  options[:serviceInstance][:servicecontent] = mock.serviceContent if options[:serviceInstance][:servicecontent].nil?
  mock.serviceInstance = mock_RbVmomi_VIM_ServiceInstance(options[:serviceInstance])

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Datastore.html
def mock_RbVmomi_VIM_Datacenter(options = {})
  options[:hostfolder_tree] = {} if options[:hostfolder_tree].nil?
  options[:vmfolder_tree]   = {} if options[:vmfolder_tree].nil?
  # Currently don't support mocking datastore tree
  options[:datastores]      = [] if options[:datastores].nil?
  options[:name]            = 'Datacenter' + rand(65536).to_s if options[:name].nil?
  options[:networks]        = [] if options[:networks].nil?

  mock = MockDatacenter.new()

  mock.name = options[:name]
  mock.hostFolder = mock_RbVmomi_VIM_Folder({ :name => 'hostFolderRoot'})
  mock.vmFolder = mock_RbVmomi_VIM_Folder({ :name => 'vmFolderRoot'})
  mock.datastore = []
  mock.network = []

  # Create vmFolder hierarchy
  recurse_folder_tree(options[:vmfolder_tree],mock.vmFolder.childEntity)

  # Create hostFolder hierarchy
  recurse_folder_tree(options[:hostfolder_tree],mock.hostFolder.childEntity)

  # Create mock Datastores
  options[:datastores].each do |datastorename|
    mock_ds = mock_RbVmomi_VIM_Datastore({ :name => datastorename })
    mock.datastore << mock_ds
  end

  # Create mock Networks
  options[:networks].each do |networkname|
    mock_nw = mock_RbVmomi_VIM_Network({ :name => networkname })
    mock.network << mock_nw
  end

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::Datacenter
  end

  mock
end

def recurse_folder_tree(tree, root_object)
  tree.keys.each do |foldername|
    folder_options = tree[foldername].nil? ? {} : tree[foldername]
    folder_options[:name] = foldername if folder_options[:name].nil?

    case folder_options[:object_type]
    when 'vm'
      child_object = mock_RbVmomi_VIM_VirtualMachine({ :name => folder_options[:name]})
    when 'compute_resource'
      child_object = mock_RbVmomi_VIM_ComputeResource({ :name => folder_options[:name]})
    when 'cluster_compute_resource'
      child_object = mock_RbVmomi_VIM_ClusterComputeResource({ :name => folder_options[:name]})
    when 'resource_pool'
      child_object =  mock_RbVmomi_VIM_ResourcePool({ :name => folder_options[:name]})
    else
      child_object = mock_RbVmomi_VIM_Folder({:name => foldername})
    end

    # Recursively create children - Default is the child_object is a Folder
    case folder_options[:object_type]
    when 'cluster_compute_resource'
      # Append children into the root Resource Pool for a cluster, instead of directly into the cluster itself.
      recurse_folder_tree(folder_options[:children],child_object.resourcePool.resourcePool) unless folder_options[:children].nil?
    when 'resource_pool'
      recurse_folder_tree(folder_options[:children],child_object.resourcePool) unless folder_options[:children].nil?
    else
      recurse_folder_tree(folder_options[:children],child_object.childEntity) unless folder_options[:children].nil?
    end

    root_object << child_object
  end
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Datastore.html
def mock_RbVmomi_VIM_Datastore(options = {})
  options[:name] = 'Datastore' + rand(65536).to_s if options[:name].nil?

  mock = MockDatastore.new()

  mock.name = options[:name]

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::Datastore
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Network.html
def mock_RbVmomi_VIM_Network(options = {})
  options[:name] = 'Network' + rand(65536).to_s if options[:name].nil?

  mock = MockNetwork.new()

  mock.name = options[:name]

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::Network
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualVmxnet3.html
def mock_RbVmomi_VIM_VirtualVmxnet3(options = {})
  options[:key] = rand(65536) if options[:key].nil?
  options[:deviceInfo] = MockDescription.new()
  options[:backing] = MockVirtualEthernetCardNetworkBackingInfo.new()
  options[:addressType] = 'assigned'
  options[:connectable] = MockVirtualDeviceConnectInfo.new()

  mock = MockVirtualVmxnet3.new()

  mock.key = options[:key]
  mock.deviceInfo = options[:deviceInfo]
  mock.backing = options[:backing]
  mock.addressType = options[:addressType]
  mock.connectable = options[:connectable]

  allow(mock).to receive(:instance_of?) do |expected_type|
    expected_type == RbVmomi::VIM::VirtualVmxnet3
  end

  mock
end

# https://pubs.vmware.com/vi3/sdk/ReferenceGuide/vim.vm.RelocateSpec.html
def mock_RbVmomi_VIM_VirtualMachineRelocateSpec(options = {})
  options[:datastore] = 'Datastore' + rand(65536).to_s if options[:datastore].nil?
  options[:diskMoveType] = :moveChildMostDiskBacking
  options[:pool] = 'Pool' + rand(65536).to_s if options[:pool].nil?

  mock = MockVirtualMachineRelocateSpec.new

  mock.datastore = mock_RbVmomi_VIM_Datastore({ :name => options[:datastore]})
  mock.diskMoveType = options[:diskMoveType]
  mock.pool = mock_RbVmomi_VIM_ResourcePool({:name => options[:pool]})
  allow(mock).to receive(:is_a?).and_return(RbVmomi::VIM::VirtualMachineRelocateSpec)
  mock
end

# https://pubs.vmware.com/vi3/sdk/ReferenceGuide/vim.vm.ConfigSpec.html
def mock_RbVmomi_VIM_VirtualMachineConfigSpec(options = {})
  options[:device] = mock_RbVmomi_VIM_VirtualVmxnet3()


  mock = MockVirtualMachineConfigSpec.new

  mock.deviceChange = []
  mock.deviceChange << { operation: :edit, device: options[:device]}

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.Datastore.html
def mock_RbVmomi_VIM_Folder(options = {})
  options[:name] = 'Folder' + rand(65536).to_s if options[:name].nil?

  mock = MockFolder.new()

  mock.name = options[:name]
  mock.childEntity = []
  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::Folder
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.HostSystem.html
def mock_RbVmomi_VIM_HostSystem(options = {})
  options[:memory_size]          = 4294967296 if options[:memory_size].nil? # 4GB RAM
  options[:num_cpu]              = 1 if options[:num_cpu].nil?
  options[:num_cores_per_cpu]    = 1 if options[:num_cores_per_cpu].nil?
  options[:cpu_speed]            = 2048 if options[:cpu_speed].nil? # 2.0 GHz 
  options[:cpu_model]            = 'Intel(R) Xeon(R) CPU E5-2697 v4 @ 2.0GHz' if options[:cpu_model].nil?
  options[:maintenance_mode]     = false if options[:maintenance_mode].nil?
  options[:overall_status]       = 'green' if options[:overall_status].nil?
  options[:overall_cpu_usage]    = 1 if options[:overall_cpu_usage].nil?
  options[:overall_memory_usage] = 1 if options[:overall_memory_usage].nil?
  options[:name]                 = 'HOST' + rand(65536).to_s if options[:name].nil?
  options[:config_issue]         = [] if options[:config_issue].nil?

  mock = MockHostSystem.new()
  mock.name = options[:name]
  mock.summary = MockHostListSummary.new()
  mock.summary.quickStats = MockHostListSummaryQuickStats.new()
  mock.summary.hardware = MockHostHardwareSummary.new()
  mock.hardware = MockHostSystemHostHardwareInfo.new()
  mock.runtime = MockHostRuntimeInfo.new()

  mock.hardware.cpuPkg = []
  (1..options[:num_cpu]).each do |cpuid|
    mockcpu = MockHostCpuPackage.new()
    mockcpu.hz = options[:cpu_speed] * 1024 * 1024
    mockcpu.description = options[:cpu_model]
    mockcpu.index = 0
    mock.hardware.cpuPkg << mockcpu
  end

  mock.runtime.inMaintenanceMode = options[:maintenance_mode]
  mock.overallStatus = options[:overall_status]
  mock.configIssue = options[:config_issue]

  mock.summary.hardware.memorySize = options[:memory_size]
  mock.hardware.memorySize = options[:memory_size]

  mock.summary.hardware.cpuMhz = options[:cpu_speed]
  mock.summary.hardware.numCpuCores = options[:num_cpu] * options[:num_cores_per_cpu]
  mock.summary.hardware.numCpuPkgs = options[:num_cpu]
  mock.summary.quickStats.overallCpuUsage = options[:overall_cpu_usage]
  mock.summary.quickStats.overallMemoryUsage = options[:overall_memory_usage]

  mock
end

# https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.query.PropertyCollector.RetrieveResult.html
def mock_RbVmomi_VIM_RetrieveResult(options = {})
  options[:response] = [] if options[:response].nil?
  mock = MockRetrieveResult.new()

  mock.objects = []

  options[:response].each do |response|
    mock_objectdata = MockObjectContent.new()

    mock_objectdata.propSet = []

    mock_objectdata.obj = response[:object] 

    # Mock the object properties
    response.each do |key,value|
      unless key == :object
        mock_property = MockDynamicProperty.new()
        mock_property.name = key
        mock_property.val = value
        mock_objectdata.propSet << mock_property
      end
    end
    mock.objects << mock_objectdata
  end

  mock
end

# https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvmodl.query.PropertyCollector.html
def mock_RbVmomi_VIM_PropertyCollector(options = {})
  mock = MockPropertyCollector.new()

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ServiceInstanceContent.html#field_detail
def mock_RbVmomi_VIM_ServiceContent(options = {})
  options[:propertyCollector] = {} if options[:propertyCollector].nil?
  options[:datacenters]       = [] if options[:datacenters].nil?

  mock = MockServiceContent.new()

  mock.searchIndex = MockSearchIndex.new()
  mock.viewManager = MockViewManager.new()
  mock.virtualDiskManager = MockVirtualDiskManager.new()
  mock.rootFolder = mock_RbVmomi_VIM_Folder({ :name => 'RootFolder' })

  mock.propertyCollector = mock_RbVmomi_VIM_PropertyCollector(options[:propertyCollector])

  # Create the DCs in this ServiceContent
  options[:datacenters].each do |dc_options|
    mock_dc = mock_RbVmomi_VIM_Datacenter(dc_options)
    mock.rootFolder.childEntity << mock_dc
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk41pubs/ApiReference/vim.ServiceInstance.html
def mock_RbVmomi_VIM_ServiceInstance(options = {})
  mock = MockServiceInstance.new()

  mock.content = options[:servicecontent]

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.Task.html
def mock_RbVmomi_VIM_Task(options = {})
  mock = MockTask.new()

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.ResourcePool.html
def mock_RbVmomi_VIM_ResourcePool(options = {})
  options[:name] = 'ResourcePool' + rand(65536).to_s if options[:name].nil?

  mock = MockResourcePool.new()

  mock.name = options[:name]
  mock.resourcePool = []
  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::ResourcePool
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualDisk.html
def mock_RbVmomi_VIM_VirtualDisk(options = {})
  options[:controllerKey] = rand(65536) if options[:controllerKey].nil?
  options[:key]           = rand(65536) if options[:key].nil?
  options[:label]         = 'SCSI' + rand(65536).to_s if options[:label].nil?
  options[:unitNumber]    = rand(65536) if options[:unitNumber].nil?

  mock = MockVirtualDisk.new()
  mock.deviceInfo = MockDescription.new()

  mock.deviceInfo.label = options[:label]
  mock.controllerKey = options[:controllerKey]
  mock.key = options[:key]
  mock.unitNumber = options[:unitNumber]

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::VirtualDisk
  end

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.VirtualMachine.html
def mock_RbVmomi_VIM_VirtualMachine(options = {})
  options[:snapshot_tree] = nil if options[:snapshot_tree].nil?
  options[:name] = 'VM' + rand(65536).to_s if options[:name].nil?
  options[:path] = [] if options[:path].nil?

  mock = MockVirtualMachine.new()
  mock.config = MockVirtualMachineConfigInfo.new()
  mock.config.hardware = MockVirtualHardware.new([])
  mock.summary = MockVirtualMachineSummary.new()
  mock.summary.runtime = MockVirtualMachineRuntimeInfo.new()
  mock.summary.guest = MockVirtualMachineGuestSummary.new()
  mock.runtime = mock.summary.runtime

  mock.name = options[:name]
  mock.summary.guest.hostName = options[:hostname]
  mock.runtime.bootTime = options[:boottime]
  mock.runtime.powerState = options[:powerstate]

  unless options[:snapshot_tree].nil?
    mock.snapshot = MockVirtualMachineSnapshotInfo.new()
    mock.snapshot.rootSnapshotList = []
    index = 0

    # Create a recursive snapshot tree
    recurse_snapshot_tree(options[:snapshot_tree],mock.snapshot.rootSnapshotList,index)
  end

  # Create an array of items that describe the path of the VM from the root folder
  # all the way to the VM itself
  mock.path = []
  options[:path].each do |path_item|
    mock_item = nil
    case path_item[:type]
    when 'folder'
      mock_item = mock_RbVmomi_VIM_Folder({ :name => path_item[:name] })
    when 'datacenter'
      mock_item = mock_RbVmomi_VIM_Datacenter({ :name => path_item[:name] })
    else
      raise("Unknown mock type #{path_item[:type]} for mock_RbVmomi_VIM_VirtualMachine")
    end
    mock.path << [mock_item,path_item[:name]]
  end
  mock.path << [mock,options[:name]]

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::VirtualMachine
  end

  mock
end

def recurse_snapshot_tree(tree, root_object, index)
  tree.keys.each do |snapshotname|
    snap_options = tree[snapshotname].nil? ? {} : tree[snapshotname]
    snap = MockVirtualMachineSnapshotTree.new()
    snap.id = index
    snap.name = snapshotname
    snap.childSnapshotList = []
    snap.description = "Snapshot #{snapshotname}"
    snap.snapshot = snap_options[:ref] unless snap_options[:ref].nil?

    # Recursively create chilren
    recurse_snapshot_tree(snap_options[:children],snap.childSnapshotList,index) unless snap_options[:children].nil?

    root_object << snap
    index += 1
  end
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualDevice.html
def mock_RbVmomi_VIM_VirtualMachineDevice(options = {})
  mock = MockVirtualDevice.new()
  mock.deviceInfo = MockDescription.new()

  mock.deviceInfo.label = options[:label]

  mock
end

# https://pubs.vmware.com/vsphere-55/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvim.vm.FileLayoutEx.FileInfo.html
def mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo(options = {})
  options[:key] = rand(65536).to_s if options[:key].nil?

  mock = MockVirtualMachineFileLayoutExFileInfo.new()

  mock.key = options[:key]
  mock.name = options[:name]
  mock.size = options[:size]
  mock.type = options[:type]
  mock.uniqueSize = options[:uniqueSize]

  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.Snapshot.html
def mock_RbVmomi_VIM_VirtualMachineSnapshot(options = {})
  mock = MockVirtualMachineSnapshot.new()
  
  mock
end

# https://www.vmware.com/support/developer/vc-sdk/visdk400pubs/ReferenceGuide/vim.vm.device.VirtualSCSIController.html
def mock_RbVmomi_VIM_VirtualSCSIController(options = {})
  options[:controllerKey]      = rand(65536) if options[:controllerKey].nil?
  options[:key]                = rand(65536) if options[:key].nil?
  options[:label]              = 'SCSI' + rand(65536).to_s if options[:label].nil?
  options[:scsiCtlrUnitNumber] = 7 if options[:scsiCtlrUnitNumber].nil?

  mock = MockVirtualSCSIController.new()
  mock.deviceInfo = MockDescription.new()

  mock.deviceInfo.label = options[:label]
  mock.controllerKey = options[:controllerKey]
  mock.key = options[:key]
  mock.scsiCtlrUnitNumber = options[:scsiCtlrUnitNumber]

  allow(mock).to receive(:is_a?) do |expected_type|
    expected_type == RbVmomi::VIM::VirtualSCSIController
  end

  mock
end
