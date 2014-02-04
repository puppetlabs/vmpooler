require 'yaml' unless defined?(YAML)
require 'rubygems' unless defined?(Gem)

class VsphereHelper
  def initialize vInfo = {}
    begin
      require 'rbvmomi'
    rescue LoadError
      raise "Unable to load RbVmomi, please ensure its installed"
    end

    Dir.chdir(File.dirname(__FILE__))

    config_file = File.expand_path('../vmware-host-pooler.yaml')
    vsphere = YAML.load_file(config_file)[:vsphere]

    @connection = RbVmomi::VIM.connect :host     => vsphere['server'],
                                       :user     => vsphere['username'],
                                       :password => vsphere['password'],
                                       :insecure => true
  end



  def find_datastore datastorename
    begin
      @connection.serviceInstance.CurrentTime
    rescue
      initialize()
    end

    datacenter = @connection.serviceInstance.find_datacenter
    datacenter.find_datastore(datastorename)
  end



  def find_folder foldername
    begin
      @connection.serviceInstance.CurrentTime
    rescue
      initialize()
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



  def find_pool poolname
    begin
      @connection.serviceInstance.CurrentTime
    rescue
      initialize()
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

    base = base.resourcePool unless base.is_a?(RbVmomi::VIM::ResourcePool) and base.respond_to?(:resourcePool)
    base
  end



  def find_vm vmname
    begin
      @connection.serviceInstance.CurrentTime
    rescue
      initialize()
    end

    @connection.searchIndex.FindByDnsName(:vmSearch => true, :dnsName => vmname)
  end



  def get_base_vm_container_from connection
    begin
      connection.serviceInstance.CurrentTime
    rescue
      initialize()
    end

    viewManager = connection.serviceContent.viewManager
    viewManager.CreateContainerView({
      :container => connection.serviceContent.rootFolder,
      :recursive => true,
      :type      => [ 'VirtualMachine' ]
    })
  end



  def close
    @connection.close
  end
end

