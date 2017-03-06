require 'spec_helper'

RSpec::Matchers.define :relocation_spec_with_host do |value|
  match { |actual| actual[:spec].host == value }
end

RSpec::Matchers.define :create_virtual_disk_with_size do |value|
  match { |actual| actual[:spec].capacityKb == value * 1024 * 1024 }
end

describe 'Vmpooler::VsphereHelper' do
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) { YAML.load(<<-EOT
---
:config:
  max_tries: 3
  retry_factor: 10
:vsphere:
  server: "vcenter.domain.local"
  username: "vcenter_user"
  password: "vcenter_password"
  insecure: true
EOT
    )
  }
  subject { Vmpooler::VsphereHelper.new(config, metrics) }

  let(:credentials) { config[:vsphere] }

  let(:connection_options) {{}}
  let(:connection) { mock_RbVmomi_VIM_Connection(connection_options) }
  let(:vmname) { 'vm1' }

  describe '#ensure_connected' do
    context 'when connection has ok' do
      it 'should not attempt to reconnect' do
        expect(subject).to receive(:connect_to_vsphere).exactly(0).times

        subject.ensure_connected(connection,credentials)
      end
    end

    context 'when connection has broken' do
      before(:each) do
        expect(connection.serviceInstance).to receive(:CurrentTime).and_raise(RuntimeError,'MockConnectionError')
      end

      it 'should not increment the connect.open metric' do
        # https://github.com/puppetlabs/vmpooler/issues/195
        expect(metrics).to receive(:increment).with('connect.open').exactly(0).times
        allow(subject).to receive(:connect_to_vsphere)

        subject.ensure_connected(connection,credentials)
      end

      it 'should call connect_to_vsphere to reconnect' do
        allow(metrics).to receive(:increment)
        allow(subject).to receive(:connect_to_vsphere).with(credentials)

        subject.ensure_connected(connection,credentials)
      end
    end
  end

  describe '#connect_to_vsphere' do
    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",nil)

      allow(RbVmomi::VIM).to receive(:connect).and_return(connection)
    end

    context 'succesful connection' do
      it 'should use the supplied credentials' do
        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => credentials['insecure']
        }).and_return(connection)
        subject.connect_to_vsphere(credentials)
      end

      it 'should honor the insecure setting' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/207')
        config[:vsphere][:insecure] = false

        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => false,
        }).and_return(connection)
        subject.connect_to_vsphere(credentials)
      end

      it 'should default to an insecure connection' do
        config[:vsphere][:insecure] = nil

        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => true
        }).and_return(connection)

        subject.connect_to_vsphere(credentials)
      end

      it 'should set the instance level connection object' do
        # NOTE - Using instance_variable_get is a code smell of code that is not testable
        expect(subject.instance_variable_get("@connection")).to be_nil
        subject.connect_to_vsphere(credentials)
        expect(subject.instance_variable_get("@connection")).to be(connection)
      end

      it 'should increment the connect.open counter' do
        expect(metrics).to receive(:increment).with('connect.open')
        subject.connect_to_vsphere(credentials)
      end
    end

    context 'connection is initially unsuccessful' do
      before(:each) do
        # NOTE - Using instance_variable_set is a code smell of code that is not testable
        subject.instance_variable_set("@connection",nil)

        # Simulate a failure and then success
        expect(RbVmomi::VIM).to receive(:connect).and_raise(RuntimeError,'MockError').ordered
        expect(RbVmomi::VIM).to receive(:connect).and_return(connection).ordered

        allow(subject).to receive(:sleep)
      end

      it 'should set the instance level connection object' do
        # NOTE - Using instance_variable_get is a code smell of code that is not testable
        expect(subject.instance_variable_get("@connection")).to be_nil
        subject.connect_to_vsphere(credentials)
        expect(subject.instance_variable_get("@connection")).to be(connection)
      end

      it 'should increment the connect.fail and then connect.open counter' do
        expect(metrics).to receive(:increment).with('connect.fail').exactly(1).times
        expect(metrics).to receive(:increment).with('connect.open').exactly(1).times
        subject.connect_to_vsphere(credentials)
      end
    end

    context 'connection is always unsuccessful' do
      before(:each) do
        # NOTE - Using instance_variable_set is a code smell of code that is not testable
        subject.instance_variable_set("@connection",nil)

        allow(RbVmomi::VIM).to receive(:connect).and_raise(RuntimeError,'MockError')
        allow(subject).to receive(:sleep)
      end

      it 'should raise an error' do
        expect{subject.connect_to_vsphere(credentials)}.to raise_error(RuntimeError,'MockError')
      end

      it 'should retry the connection attempt config.max_tries times' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/199')
        expect(RbVmomi::VIM).to receive(:connect).exactly(config[:config]['max_tries']).times.and_raise(RuntimeError,'MockError')

        begin
          # Swallow any errors
          subject.connect_to_vsphere(credentials)
        rescue
        end
      end

      it 'should increment the connect.fail counter config.max_tries times' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/199')
        expect(metrics).to receive(:increment).with('connect.fail').exactly(config[:config]['max_tries']).times

        begin
          # Swallow any errors
          subject.connect_to_vsphere(credentials)
        rescue
        end
      end

      [{:max_tries => 5, :retry_factor => 1},
       {:max_tries => 8, :retry_factor => 5},
      ].each do |testcase|
        context "Configuration set for max_tries of #{testcase[:max_tries]} and retry_facter of #{testcase[:retry_factor]}" do
          it "should sleep #{testcase[:max_tries] - 1} times between attempts with increasing timeout" do
            pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/199')
            config[:config]['max_tries'] = testcase[:max_tries]
            config[:config]['retry_factor'] = testcase[:retry_factor]

            (1..testcase[:max_tries] - 1).each do |try|
              expect(subject).to receive(:sleep).with(testcase[:retry_factor] * try).ordered
            end

            begin
              # Swallow any errors
              subject.connect_to_vsphere(credentials)
            rescue
            end
          end
        end
      end
    end
  end

  describe '#add_disk' do
    let(:datastorename) { 'datastore' }
    let(:disk_size) { 30 }
    let(:collectMultiple_response) { {} }

    let(:vm_scsi_controller) { mock_RbVmomi_VIM_VirtualSCSIController() }

    # Require at least one SCSI Controller
    let(:vm_object) {
      mock_vm = mock_RbVmomi_VIM_VirtualMachine({
        :name => vmname,
      })
      mock_vm.config.hardware.device << vm_scsi_controller

      mock_vm
    }

    # Require at least one DC with the requried datastore
    let(:connection_options) {{
      :serviceContent => {
        :datacenters => [
          { :name => 'MockDC', :datastores => [datastorename] }
        ]
      }
    }}

    let(:create_virtual_disk_task) { mock_RbVmomi_VIM_Task() }
    let(:reconfig_vm_task) { mock_RbVmomi_VIM_Task() }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      # NOTE - This method should not be using `_connection`, instead it should be using `@conection`
      # This should not be required once https://github.com/puppetlabs/vmpooler/issues/213 is resolved
      mock_ds = subject.find_datastore(datastorename)
      allow(mock_ds).to receive(:_connection).and_return(connection) unless mock_ds.nil?

      # Mocking for find_vmdks
      allow(connection.serviceContent.propertyCollector).to receive(:collectMultiple).and_return(collectMultiple_response)

      # Mocking for creating the disk
      allow(connection.serviceContent.virtualDiskManager).to receive(:CreateVirtualDisk_Task).and_return(create_virtual_disk_task)
      allow(create_virtual_disk_task).to receive(:wait_for_completion).and_return(true)

      # Mocking for adding disk to the VM
      allow(vm_object).to receive(:ReconfigVM_Task).and_return(reconfig_vm_task)
      allow(reconfig_vm_task).to receive(:wait_for_completion).and_return(true)
    end

    it 'should ensure the connection' do
      expect(subject).to receive(:ensure_connected).at_least(:once)

      subject.add_disk(vm_object,disk_size,datastorename)
    end

    context 'Succesfully addding disk' do
      it 'should return true' do
        expect(subject.add_disk(vm_object,disk_size,datastorename)).to be true
      end

      it 'should request a disk of appropriate size' do
        expect(connection.serviceContent.virtualDiskManager).to receive(:CreateVirtualDisk_Task)
          .with(create_virtual_disk_with_size(disk_size))
          .and_return(create_virtual_disk_task)


        subject.add_disk(vm_object,disk_size,datastorename)
      end
    end

    context 'Requested disk size is 0' do
      it 'should raise an error' do
        expect(subject.add_disk(vm_object,0,datastorename)).to be false
      end
    end

    context 'No datastores or datastore missing' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'MockDC', :datastores => ['missing_datastore'] }
          ]
        }
      }}

      it 'should return false' do
        expect{ subject.add_disk(vm_object,disk_size,datastorename) }.to raise_error(NoMethodError)
      end
    end

    context 'VM does not have a SCSI Controller' do
      let(:vm_object) {
        mock_vm = mock_RbVmomi_VIM_VirtualMachine({
          :name => vmname,
        })

        mock_vm
      }

      it 'should raise an error' do
        expect{ subject.add_disk(vm_object,disk_size,datastorename) }.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_datastore' do
    let(:datastorename) { 'datastore' }
    let(:datastore_list) { [] }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    context 'No datastores in the datacenter' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'MockDC', :datastores => [] }
          ]
        }
      }}

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        subject.find_datastore(datastorename)
      end

      it 'should return nil if the datastore is not found' do
        result = subject.find_datastore(datastorename)
        expect(result).to be_nil
      end
    end

    context 'Many datastores in the datacenter' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'MockDC', :datastores => ['ds1','ds2',datastorename,'ds3'] }
          ]
        }
      }}

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        subject.find_datastore(datastorename)
      end

      it 'should return nil if the datastore is not found' do
        result = subject.find_datastore('missing_datastore')
        expect(result).to be_nil
      end

      it 'should find the datastore in the datacenter' do
        result = subject.find_datastore(datastorename)
        
        expect(result).to_not be_nil
        expect(result.is_a?(RbVmomi::VIM::Datastore)).to be true
        expect(result.name).to eq(datastorename)
      end
    end
  end

  describe '#find_device' do
    let(:devicename) { 'device1' }
    let(:vm_object) {
      mock_vm = mock_RbVmomi_VIM_VirtualMachine()
      mock_vm.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})
      mock_vm.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device2'})

      mock_vm
    }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    it 'should ensure the connection' do
      expect(subject).to receive(:ensure_connected)

      subject.find_device(vm_object,devicename)
    end

    it 'should return a device if the device name matches' do
      result = subject.find_device(vm_object,devicename)

      expect(result.deviceInfo.label).to eq(devicename)
    end

    it 'should return nil if the device name does not match' do
      result = subject.find_device(vm_object,'missing_device')

      expect(result).to be_nil
    end
  end

  describe '#find_disk_controller' do
    let(:vm_object) {
      mock_vm = mock_RbVmomi_VIM_VirtualMachine()

      mock_vm
    }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    it 'should ensure the connection' do
      # TODO There's no reason for this as the connection is not used in this method
      expect(subject).to receive(:ensure_connected).at_least(:once)

      result = subject.find_disk_controller(vm_object)
    end

    it 'should return nil when there are no devices' do
      result = subject.find_disk_controller(vm_object)

      expect(result).to be_nil
    end

    [0,1,14].each do |testcase|
      it "should return a device for a single VirtualSCSIController with #{testcase} attached disks" do
        mock_scsi = mock_RbVmomi_VIM_VirtualSCSIController()
        vm_object.config.hardware.device << mock_scsi
        vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})
        vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device2'})

        # Add the disks
        (1..testcase).each do
          vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualDisk({ :controllerKey => mock_scsi.key })
        end

        result = subject.find_disk_controller(vm_object)

        expect(result).to eq(mock_scsi)
      end
    end

    [15].each do |testcase|
      it "should return nil for a single VirtualSCSIController with #{testcase} attached disks" do
        mock_scsi = mock_RbVmomi_VIM_VirtualSCSIController()
        vm_object.config.hardware.device << mock_scsi
        vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})
        vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device2'})

        # Add the disks
        (1..testcase).each do
          vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualDisk({ :controllerKey => mock_scsi.key })
        end

        result = subject.find_disk_controller(vm_object)

        expect(result).to be_nil
      end
    end

    it 'should raise if a VirtualDisk is missing a controller' do
      # Note - Typically this is not possible as a VirtualDisk requires a controller (SCSI, PVSCSI or IDE)
      mock_scsi = mock_RbVmomi_VIM_VirtualDisk()
      vm_object.config.hardware.device << mock_scsi
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device2'})

      expect{subject.find_disk_controller(vm_object)}.to raise_error(NoMethodError)
    end
  end

  describe '#find_disk_devices' do
    let(:vm_object) {
      mock_vm = mock_RbVmomi_VIM_VirtualMachine()

      mock_vm
    }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    it 'should ensure the connection' do
      # TODO There's no reason for this as the connection is not used in this method
      expect(subject).to receive(:ensure_connected)

      result = subject.find_disk_devices(vm_object)
    end

    it 'should return empty hash when there are no devices' do
      result = subject.find_disk_devices(vm_object)

      expect(result).to eq({})
    end

    it 'should return empty hash when there are no VirtualSCSIController or VirtualDisk devices' do
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device2'})

      result = subject.find_disk_devices(vm_object)

      expect(result).to eq({})
    end

    it 'should return a device for a VirtualSCSIController device with no children' do
      mock_scsi = mock_RbVmomi_VIM_VirtualSCSIController()
      vm_object.config.hardware.device << mock_scsi
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})

      result = subject.find_disk_devices(vm_object)

      expect(result.count).to eq(1)
      expect(result[mock_scsi.key]).to_not be_nil
      expect(result[mock_scsi.key]['children']).to eq([])
      expect(result[mock_scsi.key]['device']).to eq(mock_scsi)
    end

    it 'should return a device for a VirtualDisk device' do
      mock_disk = mock_RbVmomi_VIM_VirtualDisk()
      vm_object.config.hardware.device << mock_disk
      vm_object.config.hardware.device << mock_RbVmomi_VIM_VirtualMachineDevice({:label => 'device1'})

      result = subject.find_disk_devices(vm_object)

      expect(result.count).to eq(1)
      expect(result[mock_disk.controllerKey]).to_not be_nil
      expect(result[mock_disk.controllerKey]['children'][0]).to eq(mock_disk)
    end

    it 'should return one device for many VirtualDisk devices on the same controller' do
      controller1Key = rand(2000)
      controller2Key = controller1Key + 1
      mock_disk1 = mock_RbVmomi_VIM_VirtualDisk({:controllerKey => controller1Key})
      mock_disk2 = mock_RbVmomi_VIM_VirtualDisk({:controllerKey => controller1Key})
      mock_disk3 = mock_RbVmomi_VIM_VirtualDisk({:controllerKey => controller2Key})

      vm_object.config.hardware.device << mock_disk2
      vm_object.config.hardware.device << mock_disk1
      vm_object.config.hardware.device << mock_disk3

      result = subject.find_disk_devices(vm_object)

      expect(result.count).to eq(2)

      expect(result[controller1Key]).to_not be_nil
      expect(result[controller2Key]).to_not be_nil

      expect(result[controller1Key]['children']).to contain_exactly(mock_disk1,mock_disk2)
      expect(result[controller2Key]['children']).to contain_exactly(mock_disk3)
    end
  end

  describe '#find_disk_unit_number' do
    let(:vm_object) {
      mock_vm = mock_RbVmomi_VIM_VirtualMachine()

      mock_vm
    }
    let(:controller) { mock_RbVmomi_VIM_VirtualSCSIController() }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    it 'should ensure the connection' do
      # TODO There's no reason for this as the connection is not used in this method
      expect(subject).to receive(:ensure_connected).at_least(:once)

      result = subject.find_disk_unit_number(vm_object,controller)
    end

    it 'should return 0 when there are no devices' do
      result = subject.find_disk_unit_number(vm_object,controller)

      expect(result).to eq(0)
    end

    context 'with a single SCSI Controller' do
      before(:each) do
        vm_object.config.hardware.device << controller
      end

      it 'should return 1 when the host bus controller is at 0' do
        controller.scsiCtlrUnitNumber = 0

        result = subject.find_disk_unit_number(vm_object,controller)

        expect(result).to eq(1)
      end

      it 'should return the next lowest id when disks are attached' do
        expected_id = 9
        controller.scsiCtlrUnitNumber = 0

        (1..expected_id-1).each do |disk_id|
          mock_disk = mock_RbVmomi_VIM_VirtualDisk({
            :controllerKey => controller.key,
            :unitNumber => disk_id,
          })
          vm_object.config.hardware.device << mock_disk
        end
        result = subject.find_disk_unit_number(vm_object,controller)

        expect(result).to eq(expected_id)
      end

      it 'should return nil when there are no spare units' do
        controller.scsiCtlrUnitNumber = 0

        (1..15).each do |disk_id|
          mock_disk = mock_RbVmomi_VIM_VirtualDisk({
            :controllerKey => controller.key,
            :unitNumber => disk_id,
          })
          vm_object.config.hardware.device << mock_disk
        end
        result = subject.find_disk_unit_number(vm_object,controller)

        expect(result).to eq(nil)
      end
    end
  end

  describe '#find_folder' do
    let(:foldername) { 'folder'}
    let(:missing_foldername) { 'missing_folder'}

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
      allow(connection.serviceInstance).to receive(:find_datacenter).and_return(datacenter_object)
    end

    context 'with no folder hierarchy' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        subject.find_folder(foldername)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :vmfolder_tree => {
          'folder1' => nil,
          'folder2' => nil,
          foldername => nil,
          'folder3' => nil,
        }
      }) }

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        subject.find_folder(foldername)
      end

      it 'should return the folder when found' do
        result = subject.find_folder(foldername)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername)).to be_nil
      end
    end

    context 'with a VM with the same name as a folder in a single layer folder hierarchy' do
      # The folder hierarchy should include a VM with same name as folder, and appear BEFORE the
      # folder in the child list.
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :vmfolder_tree => {
          'folder1' => nil,
          'vm1' => { :object_type => 'vm', :name => foldername },
          foldername => nil,
          'folder3' => nil,
        }
      }) }

      it 'should not return a VM' do
        pending('https://github.com/puppetlabs/vmpooler/issues/204')
        result = subject.find_folder(foldername)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
        expect(result.is_a? RbVmomi::VIM::VirtualMachine).to be false
      end
    end

    context 'with a multi layer folder hierarchy' do
      let(:end_folder_name) { 'folder'}
      let(:foldername) { 'folder2/folder4/' + end_folder_name}
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :vmfolder_tree => {
          'folder1' => nil,
          'folder2' => {
            :children => {
              'folder3' => nil,
              'folder4' => {
                :children => {
                  end_folder_name => nil,
                },
              }
            },
          },
          'folder5' => nil,
        }
      }) }

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        subject.find_folder(foldername)
      end

      it 'should return the folder when found' do
        result = subject.find_folder(foldername)
        expect(result).to_not be_nil
        expect(result.name).to eq(end_folder_name)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername)).to be_nil
      end
    end

    context 'with a VM with the same name as a folder in a multi layer folder hierarchy' do
      # The folder hierarchy should include a VM with same name as folder mid-hierarchy (i.e. not at the end level)
      # and appear BEFORE the folder in the child list.
      let(:end_folder_name) { 'folder'}
      let(:foldername) { 'folder2/folder4/' + end_folder_name}
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :vmfolder_tree => {
          'folder1' => nil,
          'folder2' => {
            :children => {
              'folder3' => nil,
              'vm1' => { :object_type => 'vm', :name => 'folder4' },
              'folder4' => {
                :children => {
                  end_folder_name => nil,
                },
              }
            },
          },
          'folder5' => nil,
        }
      }) }

      it 'should not return a VM' do
        pending('https://github.com/puppetlabs/vmpooler/issues/204')
        result = subject.find_folder(foldername)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
        expect(result.is_a? RbVmomi::VIM::VirtualMachine).to be false
      end
    end
  end

  describe '#get_host_utilization' do
    let(:cpu_model) { 'vendor line type sku v4 speed' }
    let(:model) { 'v4' }
    let(:different_model) { 'different_model' }
    let(:limit) { 80 }
    let(:default_limit) { 90 }

    context "host with a different model" do
      let(:host) { mock_RbVmomi_VIM_HostSystem() }
      it 'should return nil' do
        expect(subject.get_host_utilization(host,different_model,limit)).to be_nil
      end
    end

    context "host in maintenance mode" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
        :maintenance_mode => true,
        })
      }
      it 'should return nil' do
        host.runtime.inMaintenanceMode = true

        expect(subject.get_host_utilization(host,model,limit)).to be_nil
      end
    end

    context "host with status of not green" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
        :overall_status => 'purple_alert',
        })
      }
      it 'should return nil' do
        expect(subject.get_host_utilization(host,model,limit)).to be_nil
      end
    end

    # CPU utilization
    context "host which exceeds limit in CPU utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => 100,
         :overall_memory_usage => 1,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should return nil' do
        expect(subject.get_host_utilization(host,model,limit)).to be_nil
      end
    end

    context "host which exceeds default limit in CPU utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => default_limit + 1.0,
         :overall_memory_usage => 1,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should return nil' do
        expect(subject.get_host_utilization(host,model)).to be_nil
      end
    end

    context "host which does not exceed default limit in CPU utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => default_limit,
         :overall_memory_usage => 1,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should not return nil' do
        expect(subject.get_host_utilization(host,model)).to_not be_nil
      end
    end

    # Memory utilization
    context "host which exceeds limit in Memory utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => 1,
         :overall_memory_usage => 100,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should return nil' do
        # Set the Memory Usage to 100%
        expect(subject.get_host_utilization(host,model,limit)).to be_nil
      end
    end

    context "host which exceeds default limit in Memory utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => 1,
         :overall_memory_usage => default_limit + 1.0,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should return nil' do
        expect(subject.get_host_utilization(host,model)).to be_nil
      end
    end

    context "host which does not exceed default limit in Memory utilization" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => 1,
         :overall_memory_usage => default_limit,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should not return nil' do
        expect(subject.get_host_utilization(host,model)).to_not be_nil
      end
    end

    context "host which does not exceed limits" do
      # Set CPU to 10%
      # Set Memory to 20%
      let(:host) { mock_RbVmomi_VIM_HostSystem({
         :overall_cpu_usage => 10,
         :overall_memory_usage => 20,
         :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
        })
      }
      it 'should return the sum of CPU and Memory utilization' do
        expect(subject.get_host_utilization(host,model,limit)[0]).to eq(10 + 20)
      end

      it 'should return the host' do
        expect(subject.get_host_utilization(host,model,limit)[1]).to eq(host)
      end
    end
  end

  describe '#host_has_cpu_model?' do
    let(:cpu_model) { 'vendor line type sku v4 speed' }
    let(:model) { 'v4' }
    let(:different_model) { 'different_model' }
    let(:host) { mock_RbVmomi_VIM_HostSystem({
      :cpu_model => cpu_model,
      })
    }

    it 'should return true if the model matches' do
      expect(subject.host_has_cpu_model?(host,model)).to eq(true)
    end

    it 'should return false if the model is different' do
      expect(subject.host_has_cpu_model?(host,different_model)).to eq(false)
    end
  end

  describe '#get_host_cpu_arch_version' do
    let(:cpu_model) { 'vendor line type sku v4 speed' }
    let(:model) { 'v4' }
    let(:different_model) { 'different_model' }
    let(:host) { mock_RbVmomi_VIM_HostSystem({
      :cpu_model => cpu_model,
      :num_cpu => 2,
      })
    }

    it 'should return the fifth element in the string delimited by spaces' do
      expect(subject.get_host_cpu_arch_version(host)).to eq(model)
    end

    it 'should use the description of the first CPU' do
      host.hardware.cpuPkg[0].description = 'vendor line type sku v6 speed'
      expect(subject.get_host_cpu_arch_version(host)).to eq('v6')
    end
  end

  describe '#cpu_utilization_for' do
    [{ :cpu_usage => 10.0,
       :core_speed => 10.0,
       :num_cores => 2,
       :expected_value => 50.0,
     },
     { :cpu_usage => 10.0,
       :core_speed => 10.0,
       :num_cores => 4,
       :expected_value => 25.0,
     },
     { :cpu_usage => 14.0,
       :core_speed => 12.0,
       :num_cores => 5,
       :expected_value => 23.0 + 1.0/3.0,
     },
    ].each do |testcase|
      context "CPU Usage of #{testcase[:cpu_usage]}MHz with #{testcase[:num_cores]} x #{testcase[:core_speed]}MHz cores" do
        it "should be #{testcase[:expected_value]}%" do
          host = mock_RbVmomi_VIM_HostSystem({
            :num_cores_per_cpu => testcase[:num_cores],
            :cpu_speed         => testcase[:core_speed],
            :overall_cpu_usage => testcase[:cpu_usage],
          })

          expect(subject.cpu_utilization_for(host)).to eq(testcase[:expected_value])
        end
      end
    end
  end

  describe '#memory_utilization_for' do
    [{ :memory_usage_gigbytes => 10.0,
       :memory_size_bytes => 10.0 * 1024 * 1024,
       :expected_value => 100.0,
     },
     { :memory_usage_gigbytes => 15.0,
       :memory_size_bytes => 25.0 * 1024 * 1024,
       :expected_value => 60.0,
     },
     { :memory_usage_gigbytes => 9.0,
       :memory_size_bytes => 31.0 * 1024 * 1024,
       :expected_value => 29.03225806451613,
     },
    ].each do |testcase|
      context "Memory Usage of #{testcase[:memory_usage_gigbytes]}GBytes with #{testcase[:memory_size_bytes]}Bytes of total memory" do
        it "should be #{testcase[:expected_value]}%" do
          host = mock_RbVmomi_VIM_HostSystem({
            :memory_size          => testcase[:memory_size_bytes],
            :overall_memory_usage => testcase[:memory_usage_gigbytes],
          })

          expect(subject.memory_utilization_for(host)).to eq(testcase[:expected_value])
        end
      end
    end
  end

  describe '#find_least_used_host' do
    let(:cluster_name) { 'cluster' }
    let(:missing_cluster_name) { 'missing_cluster' }
    let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      # This mocking is a little fragile but hard to do without a real vCenter instance
      allow(connection.serviceInstance).to receive(:find_datacenter).and_return(datacenter_object)
      datacenter_object.hostFolder.childEntity = [cluster_object]
    end

    context 'missing cluster' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [{
          :name => cluster_name,
      }]})}
      let(:expected_host) { cluster_object.host[0] }

      it 'should raise an error' do
        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError,/undefined method/)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError)
      end
    end

    context 'standalone host within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [{
          :name => cluster_name,
      }]})}
      let(:expected_host) { cluster_object.host[0] }

      it 'should return the standalone host' do
        result = subject.find_least_used_host(cluster_name)

        expect(result).to be(expected_host)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_host(cluster_name)
      end
    end

    context 'standalone host outside the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [{
          :name => cluster_name,
          :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024,
      }]})}
      let(:expected_host) { cluster_object.host[0] }

      it 'should raise an error' do
        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError,/undefined method/)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError)
      end
    end

    context 'cluster of 3 hosts within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [
          { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      it 'should return the standalone host' do
        result = subject.find_least_used_host(cluster_name)

        expect(result).to be(expected_host)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_host(cluster_name)
      end
    end

    context 'cluster of 3 hosts all outside of the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [
          { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      it 'should raise an error' do
        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError,/undefined method/)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        expect{subject.find_least_used_host(missing_cluster_name)}.to raise_error(NoMethodError)
      end
    end

    context 'cluster of 5 hosts of which one is out of limits and one has wrong CPU type' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [
          { :overall_cpu_usage => 31, :overall_memory_usage => 31, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :cpu_model => 'different cpu model', :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      it 'should return the standalone host' do
        result = subject.find_least_used_host(cluster_name)

        expect(result).to be(expected_host)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_host(cluster_name)
      end
    end

    context 'cluster of 3 hosts all outside of the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [
          { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
          { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      it 'should return a host' do
        pending('https://github.com/puppetlabs/vmpooler/issues/206')
        result = subject.find_least_used_host(missing_cluster_name)
        expect(result).to_not be_nil
      end

      it 'should ensure the connection' do
        pending('https://github.com/puppetlabs/vmpooler/issues/206')
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_host(cluster_name)
      end
    end
  end

  describe '#find_cluster' do
    let(:cluster) {'cluster'}
    let(:missing_cluster) {'missing_cluster'}

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
      allow(connection.serviceInstance).to receive(:find_datacenter).and_return(datacenter_object)
    end

    context 'no clusters in the datacenter' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }

      before(:each) do
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :hostfolder_tree => {
          'cluster1' =>  {:object_type => 'compute_resource'},
          'cluster2' => {:object_type => 'compute_resource'},
          cluster => {:object_type => 'compute_resource'},
          'cluster3' => {:object_type => 'compute_resource'},
        }
      }) }

      it 'should return the cluster when found' do
        result = subject.find_cluster(cluster)

        expect(result).to_not be_nil
        expect(result.name).to eq(cluster)
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster)).to be_nil
      end
    end

    context 'with a multi layer folder hierarchy' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
        :hostfolder_tree => {
          'cluster1' =>  {:object_type => 'compute_resource'},
          'folder2' => {
            :children => {
              cluster => {:object_type => 'compute_resource'},
            }
          },
          'cluster3' => {:object_type => 'compute_resource'},
        }
      }) }

      it 'should return the cluster when found' do
        pending('https://github.com/puppetlabs/vmpooler/issues/205')
        result = subject.find_cluster(cluster)

        expect(result).to_not be_nil
        expect(result.name).to eq(cluster)
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster)).to be_nil
      end
    end
  end

  describe '#get_cluster_host_utilization' do
    context 'standalone host within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [{}]}) }
      
      it 'should return array with one element' do
        result = subject.get_cluster_host_utilization(cluster_object)
        expect(result).to_not be_nil
        expect(result.count).to eq(1)
      end
    end

    context 'standalone host which is out the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      
      it 'should return array with 0 elements' do
        result = subject.get_cluster_host_utilization(cluster_object)
        expect(result).to_not be_nil
        expect(result.count).to eq(0)
      end
    end

    context 'cluster with 3 hosts within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      
      it 'should return array with 3 elements' do
        result = subject.get_cluster_host_utilization(cluster_object)
        expect(result).to_not be_nil
        expect(result.count).to eq(3)
      end
    end

    context 'cluster with 5 hosts of which 3 within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      
      it 'should return array with 3 elements' do
        result = subject.get_cluster_host_utilization(cluster_object)
        expect(result).to_not be_nil
        expect(result.count).to eq(3)
      end
    end

    context 'cluster with 3 hosts of which none are within the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      
      it 'should return array with 0 elements' do
        result = subject.get_cluster_host_utilization(cluster_object)
        expect(result).to_not be_nil
        expect(result.count).to eq(0)
      end
    end
  end

  describe '#find_least_used_compatible_host' do
    let(:vm) { mock_RbVmomi_VIM_VirtualMachine() }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
    end

    context 'standalone host within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [{}]}) }
      let(:standalone_host) { cluster_object.host[0] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = standalone_host
      end

      it 'should return the standalone host' do
        result = subject.find_least_used_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(standalone_host)
        expect(result[1]).to eq(standalone_host.name)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_compatible_host(vm)
      end
    end

    context 'standalone host outside of limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:standalone_host) { cluster_object.host[0] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = standalone_host
      end

      it 'should raise error' do
        expect{subject.find_least_used_compatible_host(vm)}.to raise_error(NoMethodError,/undefined method/)
      end
    end

    context 'cluster of 3 hosts within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = expected_host
      end

      it 'should return the least used host' do
        result = subject.find_least_used_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(expected_host)
        expect(result[1]).to eq(expected_host.name)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_compatible_host(vm)
      end
    end

    context 'cluster of 3 hosts all outside of the limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = expected_host
      end

      it 'should raise error' do
        expect{subject.find_least_used_compatible_host(vm)}.to raise_error(NoMethodError,/undefined method/)
      end
    end

    context 'cluster of 5 hosts of which one is out of limits and one has wrong CPU type' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 31, :overall_memory_usage => 31, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :cpu_model => 'different cpu model', :overall_cpu_usage => 1, :overall_memory_usage => 1, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 11, :overall_memory_usage => 11, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 100, :overall_memory_usage => 100, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 21, :overall_memory_usage => 21, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[2] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = expected_host
      end

      it 'should return the least used host' do
        result = subject.find_least_used_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(expected_host)
        expect(result[1]).to eq(expected_host.name)
      end

      it 'should ensure the connection' do
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_compatible_host(vm)
      end
    end

    context 'cluster of 3 hosts all with the same utilisation' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [
        { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
        { :overall_cpu_usage => 10, :overall_memory_usage => 10, :cpu_speed => 100, :num_cores_per_cpu => 1, :num_cpu => 1, :memory_size => 100.0 * 1024 * 1024 },
      ]}) }
      let(:expected_host) { cluster_object.host[1] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = expected_host
      end

      it 'should return a host' do
        pending('https://github.com/puppetlabs/vmpooler/issues/206 is fixed')
        result = subject.find_least_used_compatible_host(vm)

        expect(result).to_not be_nil
      end

      it 'should ensure the connection' do
        pending('https://github.com/puppetlabs/vmpooler/issues/206 is fixed')
        expect(subject).to receive(:ensure_connected)

        result = subject.find_least_used_compatible_host(vm)
      end
    end
  end

  describe '#find_pool' do
    let(:poolname) { 'pool'}
    let(:missing_poolname) { 'missing_pool'}

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)
      allow(connection.serviceInstance).to receive(:find_datacenter).and_return(datacenter_object)
    end

    context 'with empty folder hierarchy' do
      let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }

      it 'should ensure the connection' do
        pending('https://github.com/puppetlabs/vmpooler/issues/209')
        expect(subject).to receive(:ensure_connected)

        subject.find_pool(poolname)
      end

      it 'should return nil if the pool is not found' do
        pending('https://github.com/puppetlabs/vmpooler/issues/209')
        expect(subject.find_pool(missing_poolname)).to be_nil
      end
    end

    [
    # Single layer Host folder hierarchy
    {
      :context => 'single layer folder hierarchy with a resource pool',
      :poolpath => 'pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => nil,
        'pool' => {:object_type => 'resource_pool'},
        'folder3' => nil,
      },
    },
    {
      :context => 'single layer folder hierarchy with a child resource pool',
      :poolpath => 'parentpool/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => nil,
        'parentpool' => {:object_type => 'resource_pool', :children => {
          'pool' => {:object_type => 'resource_pool'},
        }},
        'folder3' => nil,
      },
    },
    {
      :context => 'single layer folder hierarchy with a resource pool within a cluster',
      :poolpath => 'cluster/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => nil,
        'cluster' => {:object_type => 'cluster_compute_resource', :children => {
          'pool' => {:object_type => 'resource_pool'},
        }},
        'folder3' => nil,
      },
    },
    # Multi layer Host folder hierarchy
    {
      :context => 'multi layer folder hierarchy with a resource pool',
      :poolpath => 'folder2/folder4/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => { :children => {
          'folder3' => nil,
          'folder4' => { :children => {
            'pool' => {:object_type => 'resource_pool'},
          }},
        }},
        'folder5' => nil,
      },
    },
    {
      :context => 'multi layer folder hierarchy with a child resource pool',
      :poolpath => 'folder2/folder4/parentpool/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => { :children => {
          'folder3' => nil,
          'folder4' => { :children => {
            'parentpool' => {:object_type => 'resource_pool', :children => {
              'pool' => {:object_type => 'resource_pool'},
            }},
          }},
        }},
        'folder5' => nil,
      },
    },
    {
      :context => 'multi layer folder hierarchy with a resource pool within a cluster',
      :poolpath => 'folder2/folder4/cluster/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => { :children => {
          'folder3' => nil,
          'folder4' => { :children => {
            'cluster' => {:object_type => 'cluster_compute_resource', :children => {
              'pool' => {:object_type => 'resource_pool'},
            }},
          }},
        }},
        'folder5' => nil,
      },
    },
    ].each do |testcase|
      context testcase[:context] do
        let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({ :hostfolder_tree => testcase[:hostfolder_tree]}) }

        it 'should ensure the connection' do
          expect(subject).to receive(:ensure_connected)

          subject.find_pool(testcase[:poolpath])
        end

        it 'should return the pool when found' do
          result = subject.find_pool(testcase[:poolpath])

          expect(result).to_not be_nil
          expect(result.name).to eq(testcase[:poolname])
          expect(result.is_a?(RbVmomi::VIM::ResourcePool)).to be true
        end

        it 'should return nil if the poolname is not found' do
          pending('https://github.com/puppetlabs/vmpooler/issues/209')
          expect(subject.find_pool(missing_poolname)).to be_nil
        end
      end
    end

    # Tests for issue https://github.com/puppetlabs/vmpooler/issues/210
    [
    {
      :context => 'multi layer folder hierarchy with a resource pool the same name as a folder',
      :poolpath => 'folder2/folder4/cluster/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => { :children => {
          'folder3' => nil,
          'bad_pool' => {:object_type => 'resource_pool', :name => 'folder4'},
          'folder4' => { :children => {
            'cluster' => {:object_type => 'cluster_compute_resource', :children => {
              'pool' => {:object_type => 'resource_pool'},
            }},
          }},
        }},
        'folder5' => nil,
      },
    },
    {
      :context => 'multi layer folder hierarchy with a cluster the same name as a folder',
      :poolpath => 'folder2/folder4/cluster/pool',
      :poolname => 'pool',
      :hostfolder_tree => {
        'folder1' => nil,
        'folder2' => { :children => {
          'folder3' => nil,
          'bad_cluster' => {:object_type => 'cluster_compute_resource', :name => 'folder4'},
          'folder4' => { :children => {
            'cluster' => {:object_type => 'cluster_compute_resource', :children => {
              'pool' => {:object_type => 'resource_pool'},
            }},
          }},
        }},
        'folder5' => nil,
      },
    },
    ].each do |testcase|
      context testcase[:context] do
        let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({ :hostfolder_tree => testcase[:hostfolder_tree]}) }

        it 'should ensure the connection' do
          pending('https://github.com/puppetlabs/vmpooler/issues/210')
          expect(subject).to receive(:ensure_connected)

          subject.find_pool(testcase[:poolpath])
        end

        it 'should return the pool when found' do
          pending('https://github.com/puppetlabs/vmpooler/issues/210')
          result = subject.find_pool(testcase[:poolpath])

          expect(result).to_not be_nil
          expect(result.name).to eq(testcase[:poolname])
          expect(result.is_a?(RbVmomi::VIM::ResourcePool)).to be true
        end
      end
    end
  end

  describe '#find_snapshot' do
    let(:snapshot_name) {'snapshot'}
    let(:missing_snapshot_name) {'missing_snapshot'}
    let(:vm) { mock_RbVmomi_VIM_VirtualMachine(mock_options) }
    let(:snapshot_object) { mock_RbVmomi_VIM_VirtualMachine() }

    context 'VM with no snapshots' do
      let(:mock_options) {{ :snapshot_tree => nil }}
      it 'should return nil' do
        expect(subject.find_snapshot(vm,snapshot_name)).to be_nil
      end
    end

    context 'VM with a single layer of snapshots' do
      let(:mock_options) {{
        :snapshot_tree => {
          'snapshot1' => nil,
          'snapshot2' => nil,
          'snapshot3'  => nil,
          'snapshot4' => nil,
          snapshot_name => { :ref => snapshot_object},
        }
      }}

      it 'should return snapshot which matches the name' do
        result = subject.find_snapshot(vm,snapshot_name)
        expect(result).to be(snapshot_object)
      end

      it 'should return nil which no matches are found' do
        result = subject.find_snapshot(vm,missing_snapshot_name)
        expect(result).to be_nil
      end
    end

    context 'VM with a nested layers of snapshots' do
      let(:mock_options) {{
        :snapshot_tree => {
          'snapshot1' => nil,
          'snapshot2' => nil,
          'snapshot3'  => { :children => {
            'snapshot4' => nil,
            'snapshot5' => { :children => {
              snapshot_name => { :ref => snapshot_object},
            }},
          }},
          'snapshot6' => nil,
        }
      }}

      it 'should return snapshot which matches the name' do
        result = subject.find_snapshot(vm,snapshot_name)
        expect(result).to be(snapshot_object)
      end

      it 'should return nil which no matches are found' do
        result = subject.find_snapshot(vm,missing_snapshot_name)
        expect(result).to be_nil
      end
    end
  end

  describe '#find_vm' do
    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      allow(subject).to receive(:find_vm_light).and_return('vmlight')
      allow(subject).to receive(:find_vm_heavy).and_return( { vmname => 'vmheavy' })
    end

    it 'should ensure the connection' do
      # TODO This seems like overkill as we immediately call vm_light and heavy which
      # does the same thing.  Also the connection isn't actually used in this method
      expect(subject).to receive(:ensure_connected)

      subject.find_vm(vmname)
    end

    it 'should call find_vm_light' do
      expect(subject).to receive(:find_vm_light).and_return('vmlight')

      expect(subject.find_vm(vmname)).to eq('vmlight')
    end

    it 'should not call find_vm_heavy if find_vm_light finds the VM' do
      expect(subject).to receive(:find_vm_light).and_return('vmlight')
      expect(subject).to receive(:find_vm_heavy).exactly(0).times

      expect(subject.find_vm(vmname)).to eq('vmlight')
    end

    it 'should call find_vm_heavy when find_vm_light returns nil' do
      expect(subject).to receive(:find_vm_light).and_return(nil)
      expect(subject).to receive(:find_vm_heavy).and_return( { vmname => 'vmheavy' })

      expect(subject.find_vm(vmname)).to eq('vmheavy')
    end
  end

  describe '#find_vm_light' do
    let(:missing_vm) { 'missing_vm' }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      allow(connection.searchIndex).to receive(:FindByDnsName).and_return(nil)
    end

    it 'should ensure the connection' do
      expect(subject).to receive(:ensure_connected)

      subject.find_vm_light(vmname)
    end

    it 'should call FindByDnsName with the correct parameters' do
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: vmname,
      })

      subject.find_vm_light(vmname)
    end

    it 'should return the VM object when found' do
      vm_object = mock_RbVmomi_VIM_VirtualMachine()
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: vmname,
      }).and_return(vm_object)

      expect(subject.find_vm_light(vmname)).to be(vm_object)
    end

    it 'should return nil if the VM is not found' do
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: missing_vm,
      }).and_return(nil)

      expect(subject.find_vm_light(missing_vm)).to be_nil
    end
  end

  describe '#find_vm_heavy' do
    let(:missing_vm) { 'missing_vm' }
    # Return an empty result by default
    let(:retrieve_result) {{}}

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      allow(connection.propertyCollector).to receive(:RetrievePropertiesEx).and_return(mock_RbVmomi_VIM_RetrieveResult(retrieve_result))
    end

    it 'should ensure the connection' do
      expect(subject).to receive(:ensure_connected).at_least(:once)

      subject.find_vm_heavy(vmname)
    end

    context 'Search result is empty' do
      it 'should return empty hash' do
        expect(subject.find_vm_heavy(vmname)).to eq({})
      end
    end

    context 'Search result contains VMs but no matches' do
      let(:retrieve_result) {
        { :response => [
          { 'name' => 'no_match001'},
          { 'name' => 'no_match002'},
          { 'name' => 'no_match003'},
          { 'name' => 'no_match004'},
         ]
        }
      }

      it 'should return empty hash' do
        expect(subject.find_vm_heavy(vmname)).to eq({})
      end
    end

    context 'Search contains a single match' do
      let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
      let(:retrieve_result) {
        { :response => [
          { 'name' => 'no_match001'},
          { 'name' => 'no_match002'},
          { 'name' => vmname, :object => vm_object },
          { 'name' => 'no_match003'},
          { 'name' => 'no_match004'},
         ]
        }
      }

      it 'should return single result' do
        result = subject.find_vm_heavy(vmname)
        expect(result.keys.count).to eq(1)
      end

      it 'should return the matching VM Object' do
        result = subject.find_vm_heavy(vmname)
        expect(result[vmname]).to be(vm_object)
      end
    end

    context 'Search contains a two matches' do
      let(:vm_object1) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
      let(:vm_object2) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
      let(:retrieve_result) {
        { :response => [
          { 'name' => 'no_match001'},
          { 'name' => 'no_match002'},
          { 'name' => vmname, :object => vm_object1 },
          { 'name' => 'no_match003'},
          { 'name' => 'no_match004'},
          { 'name' => vmname, :object => vm_object2 },
         ]
        }
      }

      it 'should return one result' do
        result = subject.find_vm_heavy(vmname)
        expect(result.keys.count).to eq(1)
      end

      it 'should return the last matching VM Object' do
        result = subject.find_vm_heavy(vmname)
        expect(result[vmname]).to be(vm_object2)
      end
    end
  end

  describe '#find_vmdks' do
    let(:datastorename) { 'datastore' }
    let(:connection_options) {{
      :serviceContent => {
        :datacenters => [
          { :name => 'MockDC', :datastores => [datastorename] }
        ]
      }
    }}

    let(:collectMultiple_response) { {} }

    before(:each) do
      # NOTE - Using instance_variable_set is a code smell of code that is not testable
      subject.instance_variable_set("@connection",connection)

      # NOTE - This method should not be using `_connection`, instead it should be using `@conection`
      mock_ds = subject.find_datastore(datastorename)
      allow(mock_ds).to receive(:_connection).and_return(connection)
      allow(connection.serviceContent.propertyCollector).to receive(:collectMultiple).and_return(collectMultiple_response)
    end

    it 'should not use _connction to get the underlying connection object' do
      pending('https://github.com/puppetlabs/vmpooler/issues/213')

      mock_ds = subject.find_datastore(datastorename)
      expect(mock_ds).to receive(:_connection).exactly(0).times

      begin
        # ignore all errors. What's important is that it doesn't call _connection
        subject.find_vmdks(vmname,datastorename)
      rescue
      end
    end

    it 'should ensure the connection' do
      expect(subject).to receive(:ensure_connected).at_least(:once)

      subject.find_vmdks(vmname,datastorename)
    end

    context 'Searching all files for all VMs on a Datastore' do
      # This is fairly fragile mocking
      let(:collectMultiple_response) { {
        'FakeVMObject1' => { 'layoutEx.file' =>
        [
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 101, :name => "[#{datastorename}] mock1/mock1_0.vmdk"})
        ]},
        vmname => { 'layoutEx.file' =>
        [
          # VMDKs which should match
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 1, :name => "[#{datastorename}] #{vmname}/#{vmname}_0.vmdk"}),
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 2, :name => "[#{datastorename}] #{vmname}/#{vmname}_1.vmdk"}),
          # VMDKs which should not match
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 102, :name => "[otherdatastore] #{vmname}/#{vmname}_0.vmdk"}),
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 103, :name => "[otherdatastore] #{vmname}/#{vmname}.vmdk"}),
          mock_RbVmomi_VIM_VirtualMachineFileLayoutExFileInfo({ :key => 104, :name => "[otherdatastore] #{vmname}/#{vmname}_abc.vmdk"}),
        ]},
      } }

      it 'should return empty array if no VMDKs match the VM name' do
        expect(subject.find_vmdks('missing_vm_name',datastorename)).to eq([])
      end

      it 'should return matching VMDKs for the VM' do
        result = subject.find_vmdks(vmname,datastorename)
        expect(result).to_not be_nil
        expect(result.count).to eq(2)
        # The keys for each VMDK should be less that 100 as per the mocks
        result.each do |fileinfo|
          expect(fileinfo.key).to be < 100
        end
      end
    end
  end

  describe '#get_base_vm_container_from' do
    let(:local_connection) { mock_RbVmomi_VIM_Connection() }

     before(:each) do
       allow(subject).to receive(:ensure_connected)
     end

    it 'should ensure the connection' do
      pending('https://github.com/puppetlabs/vmpooler/issues/212')
      expect(subject).to receive(:ensure_connected).with(local_connection,credentials)

      subject.get_base_vm_container_from(local_connection)
    end

    it 'should return a recursive view of type VirtualMachine' do
      result = subject.get_base_vm_container_from(local_connection)

      expect(result.recursive).to be true
      expect(result.type).to eq(['VirtualMachine'])
    end
  end

  describe '#get_snapshot_list' do
    let(:snapshot_name) {'snapshot'}
    let(:snapshot_tree) { mock_RbVmomi_VIM_VirtualMachine(mock_options).snapshot.rootSnapshotList }
    let(:snapshot_object) { mock_RbVmomi_VIM_VirtualMachine() }

    it 'should raise if the snapshot tree is nil' do
      expect{ subject.get_snapshot_list(nil,snapshot_name)}.to raise_error(NoMethodError)
    end

    context 'VM with a single layer of snapshots' do
      let(:mock_options) {{
        :snapshot_tree => {
          'snapshot1' => nil,
          'snapshot2' => nil,
          'snapshot3'  => nil,
          'snapshot4' => nil,
          snapshot_name => { :ref => snapshot_object},
        }
      }}

      it 'should return snapshot which matches the name' do
        result = subject.get_snapshot_list(snapshot_tree,snapshot_name)
        expect(result).to be(snapshot_object)
      end
    end

    context 'VM with a nested layers of snapshots' do
      let(:mock_options) {{
        :snapshot_tree => {
          'snapshot1' => nil,
          'snapshot2' => nil,
          'snapshot3'  => { :children => {
            'snapshot4' => nil,
            'snapshot5' => { :children => {
              snapshot_name => { :ref => snapshot_object},
            }},
          }},
          'snapshot6' => nil,
        }
      }}

      it 'should return snapshot which matches the name' do
        result = subject.get_snapshot_list(snapshot_tree,snapshot_name)
        expect(result).to be(snapshot_object)
      end
    end
  end

  describe '#migrate_vm_host' do
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
    let(:host_object) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST' })}
    let(:relocate_task) { mock_RbVmomi_VIM_Task() }

    before(:each) do
      allow(vm_object).to receive(:RelocateVM_Task).and_return(relocate_task)
      allow(relocate_task).to receive(:wait_for_completion)
    end

    it 'should call RelovateVM_Task' do
      expect(vm_object).to receive(:RelocateVM_Task).and_return(relocate_task)

      subject.migrate_vm_host(vm_object,host_object)
    end

    it 'should use a Relocation Spec object with correct host' do
      expect(vm_object).to receive(:RelocateVM_Task).with(relocation_spec_with_host(host_object))

      subject.migrate_vm_host(vm_object,host_object)
    end

    it 'should wait for the relocation to complete' do
      expect(relocate_task).to receive(:wait_for_completion)

      subject.migrate_vm_host(vm_object,host_object)
    end

    it 'should return the result of the relocation' do
      expect(relocate_task).to receive(:wait_for_completion).and_return('RELOCATE_RESULT')

      expect(subject.migrate_vm_host(vm_object,host_object)).to eq('RELOCATE_RESULT')
    end
  end

  describe '#close' do
    context 'no connection has been made' do
      before(:each) do
        # NOTE - Using instance_variable_set is a code smell of code that is not testable
        subject.instance_variable_set("@connection",nil)
      end

      it 'should not error' do
        pending('https://github.com/puppetlabs/vmpooler/issues/211')
        subject.close
      end
    end

    context 'on an open connection' do
      before(:each) do
        # NOTE - Using instance_variable_set is a code smell of code that is not testable
        subject.instance_variable_set("@connection",connection)
      end

      it 'should close the underlying connection object' do
        expect(connection).to receive(:close)
        subject.close
      end
    end
  end
end
