require 'spec_helper'

RSpec::Matchers.define :relocation_spec_with_host do |value|
  match { |actual| actual[:spec].host == value }
end

RSpec::Matchers.define :create_virtual_disk_with_size do |value|
  match { |actual| actual[:spec].capacityKb == value * 1024 * 1024 }
end

RSpec::Matchers.define :create_vm_spec do |new_name,target_folder_name,datastore|
  match { |actual|
    # Should have the correct new name
    actual[:name] == new_name &&
    # Should be in the new folder
    actual[:folder].name == target_folder_name &&
    # Should be poweredOn after clone
    actual[:spec].powerOn == true &&
    # Should be on the correct datastore
    actual[:spec][:location].datastore.name == datastore &&
    # Should contain annotation data
    actual[:spec][:config].annotation != '' &&
    # Should contain VIC information
    actual[:spec][:config].extraConfig[0][:key] == 'guestinfo.hostname' &&
    actual[:spec][:config].extraConfig[0][:value] == new_name
  }
end

RSpec::Matchers.define :create_snapshot_spec do |new_snapshot_name|
  match { |actual|
    # Should have the correct new name
    actual[:name] == new_snapshot_name &&
    # Should snapshot the memory too
    actual[:memory] == true &&
    # Should quiesce the disk
    actual[:quiesce] == true
  }
end

describe 'Vmpooler::PoolManager::Provider::VSphere' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:poolname) { 'pool1'}
  let(:provider_options) { { 'param' => 'value' } }
  let(:datacenter_name) { 'MockDC' }
  let(:config) { YAML.load(<<-EOT
---
:config:
  max_tries: 3
  retry_factor: 10
:providers:
  :vsphere:
    server: "vcenter.domain.local"
    username: "vcenter_user"
    password: "vcenter_password"
    insecure: true
    # Drop the connection pool timeout way down for spec tests so they fail fast
    connection_pool_timeout: 1
    datacenter: MockDC
:pools:
  - name: '#{poolname}'
    alias: [ 'mockpool' ]
    template: 'Templates/pool1'
    folder: 'Pooler/pool1'
    datastore: 'datastore0'
    size: 5
    timeout: 10
    ready_ttl: 1440
    clone_target: 'cluster1'
EOT
    )
  }

  let(:connection_options) {{}}
  let(:connection) { mock_RbVmomi_VIM_Connection(connection_options) }
  let(:vmname) { 'vm1' }

  subject { Vmpooler::PoolManager::Provider::VSphere.new(config, logger, metrics, 'vsphere', provider_options) }

  before(:each) do
    allow(subject).to receive(:vsphere_connection_ok?).and_return(true)
  end

  describe '#name' do
    it 'should be vsphere' do
      expect(subject.name).to eq('vsphere')
    end
  end

  describe '#vms_in_pool' do
    let(:folder_object) { mock_RbVmomi_VIM_Folder({ :name => 'pool1'}) }
    let(:pool_config) { config[:pools][0] }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    context 'Given a pool folder that is missing' do
      before(:each) do
        expect(subject).to receive(:find_folder).with(pool_config['folder'],connection,datacenter_name).and_return(nil)
      end

      it 'should get a connection' do
        expect(subject).to receive(:connect_to_vsphere).and_return(connection)

        subject.vms_in_pool(poolname)
      end

      it 'should return an empty array' do
        result = subject.vms_in_pool(poolname)

        expect(result).to eq([])
      end
    end

    context 'Given an empty pool folder' do
      before(:each) do
        expect(subject).to receive(:find_folder).with(pool_config['folder'],connection,datacenter_name).and_return(folder_object)
      end

      it 'should get a connection' do
        expect(subject).to receive(:connect_to_vsphere).and_return(connection)

        subject.vms_in_pool(poolname)
      end

      it 'should return an empty array' do
        result = subject.vms_in_pool(poolname)

        expect(result).to eq([])
      end
    end

    context 'Given a pool folder with many VMs' do
      let(:expected_vm_list) {[
        { 'name' => 'vm1'},
        { 'name' => 'vm2'},
        { 'name' => 'vm3'}
      ]}
      before(:each) do
        expected_vm_list.each do |vm_hash|
          mock_vm = mock_RbVmomi_VIM_VirtualMachine({ :name => vm_hash['name'] })
          # Add the mocked VM to the folder
          folder_object.childEntity << mock_vm
        end

        expect(subject).to receive(:find_folder).with(pool_config['folder'],connection,datacenter_name).and_return(folder_object)
      end

      it 'should get a connection' do
        expect(subject).to receive(:connect_to_vsphere).and_return(connection)

        subject.vms_in_pool(poolname)
      end

      it 'should list all VMs in the VM folder for the pool' do
        result = subject.vms_in_pool(poolname)

        expect(result).to eq(expected_vm_list)
      end
    end
  end

  describe '#get_vm' do
    let(:vm_object) { nil }
    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
      expect(subject).to receive(:find_vm).with(vmname,connection).and_return(vm_object)
    end

    context 'when VM does not exist' do
      it 'should return nil' do
        expect(subject.get_vm(poolname,vmname)).to be_nil
      end
    end

    context 'when VM exists but is missing information' do
      let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({
          :name => vmname,
        })
      }

      it 'should return a hash' do
        expect(subject.get_vm(poolname,vmname)).to be_kind_of(Hash)
      end

      it 'should return the VM name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['name']).to eq(vmname)
      end

      ['hostname','template','poolname','boottime','powerstate'].each do |testcase|
        it "should return nil for #{testcase}" do
          result = subject.get_vm(poolname,vmname)

          expect(result[testcase]).to be_nil
        end
      end
    end

    context 'when VM exists and contains all information' do
      let(:vm_hostname) { "#{vmname}.demo.local" }
      let(:boot_time) { Time.now }
      let(:power_state) { 'MockPowerState' }

      let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({
          :name => vmname,
          :hostname => vm_hostname,
          :powerstate => power_state,
          :boottime => boot_time,
          # This path should match the folder in the mocked pool in the config above
          :path => [
            { :type => 'folder',     :name => 'Datacenters' },
            { :type => 'datacenter', :name => 'DC01' },
            { :type => 'folder',     :name => 'vm' },
            { :type => 'folder',     :name => 'Pooler' },
            { :type => 'folder',     :name => 'pool1'},
          ]
        })
      }
      let(:pool_info) { config[:pools][0]}

      it 'should return a hash' do
        expect(subject.get_vm(poolname,vmname)).to be_kind_of(Hash)
      end

      it 'should return the VM name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['name']).to eq(vmname)
      end

      it 'should return the VM hostname' do
        result = subject.get_vm(poolname,vmname)

        expect(result['hostname']).to eq(vm_hostname)
      end

      it 'should return the template name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['template']).to eq(pool_info['template'])
      end

      it 'should return the pool name' do
        result = subject.get_vm(poolname,vmname)

        expect(result['poolname']).to eq(pool_info['name'])
      end

      it 'should return the boot time' do
        result = subject.get_vm(poolname,vmname)

        expect(result['boottime']).to eq(boot_time)
      end

      it 'should return the powerstate' do
        result = subject.get_vm(poolname,vmname)

        expect(result['powerstate']).to eq(power_state)
      end

    end
  end

  describe '#create_vm' do
    let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter({
      :datastores => ['datastore0'],
      :vmfolder_tree => {
        'Templates' => { :children => {
          'pool1' => { :object_type => 'vm', :name => 'pool1' },
        }},
        'Pooler' => { :children => {
          'pool1' => nil,
        }},
      },
      :hostfolder_tree => {
        'cluster1' =>  {:object_type => 'compute_resource'},
      }
    })
    }

    let(:clone_vm_task) { mock_RbVmomi_VIM_Task() }
    let(:new_vm_object)  { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname }) }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
      allow(connection.serviceInstance).to receive(:find_datacenter).and_return(datacenter_object)
    end

    context 'Given an invalid pool name' do
      it 'should raise an error' do
        expect{ subject.create_vm('missing_pool', vmname) }.to raise_error(/missing_pool does not exist/)
      end
    end

    context 'Given an invalid template path in the pool config' do
      before(:each) do
        config[:pools][0]['template'] = 'bad_template'
      end

      it 'should raise an error' do
        expect{ subject.create_vm(poolname, vmname) }.to raise_error(/did specify a full path for the template/)
      end
    end

    context 'Given a template path that does not exist' do
      before(:each) do
        config[:pools][0]['template'] = 'missing_Templates/pool1'
      end

      it 'should raise an error' do
        expect{ subject.create_vm(poolname, vmname) }.to raise_error(/specifies a template folder of .+ which does not exist/)
      end
    end

    context 'Given a template VM that does not exist' do
      before(:each) do
        config[:pools][0]['template'] = 'Templates/missing_template'
      end

      it 'should raise an error' do
        expect{ subject.create_vm(poolname, vmname) }.to raise_error(/specifies a template VM of .+ which does not exist/)
      end
    end

    context 'Given a successful creation' do
      before(:each) do
        template_vm = subject.find_folder('Templates',connection,datacenter_name).find('pool1')
        allow(template_vm).to receive(:CloneVM_Task).and_return(clone_vm_task)
        allow(clone_vm_task).to receive(:wait_for_completion).and_return(new_vm_object)
      end

      it 'should return a hash' do
        result = subject.create_vm(poolname, vmname)

        expect(result.is_a?(Hash)).to be true
      end

      it 'should use the appropriate Create_VM spec' do
        template_vm = subject.find_folder('Templates',connection,datacenter_name).find('pool1')
        expect(template_vm).to receive(:CloneVM_Task)
          .with(create_vm_spec(vmname,'pool1','datastore0'))
          .and_return(clone_vm_task)

        subject.create_vm(poolname, vmname)
      end

      it 'should have the new VM name' do
        result = subject.create_vm(poolname, vmname)

        expect(result['name']).to eq(vmname)
      end
    end
  end

  describe '#create_disk' do
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname }) }
    let(:datastorename) { 'datastore0' }
    let(:disk_size) { 10 }
    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
      allow(subject).to receive(:find_vm).with(vmname, connection).and_return(vm_object)
    end

    context 'Given an invalid pool name' do
      it 'should raise an error' do
        expect{ subject.create_disk('missing_pool',vmname,disk_size) }.to raise_error(/missing_pool does not exist/)
      end
    end

    context 'Given a missing datastore in the pool config' do
      before(:each) do
        config[:pools][0]['datastore'] = nil
      end

      it 'should raise an error' do
        expect{ subject.create_disk(poolname,vmname,disk_size) }.to raise_error(/does not have a datastore defined/)
      end
    end

    context 'when VM does not exist' do
      before(:each) do
        expect(subject).to receive(:find_vm).with(vmname, connection).and_return(nil)
      end

      it 'should raise an error' do
        expect{ subject.create_disk(poolname,vmname,disk_size) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when adding the disk raises an error' do
      before(:each) do
        expect(subject).to receive(:add_disk).and_raise(RuntimeError,'Mock Disk Error')
      end

      it 'should raise an error' do
        expect{ subject.create_disk(poolname,vmname,disk_size) }.to raise_error(/Mock Disk Error/)
      end
    end

    context 'when adding the disk succeeds' do
      before(:each) do
        expect(subject).to receive(:add_disk).with(vm_object, disk_size, datastorename, connection, datacenter_name)
      end

      it 'should return true' do
        expect(subject.create_disk(poolname,vmname,disk_size)).to be true
      end
    end
  end

  describe '#create_snapshot' do
    let(:snapshot_task) { mock_RbVmomi_VIM_Task() }
    let(:snapshot_name) { 'snapshot' }
    let(:snapshot_tree) {{}}
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname, :snapshot_tree => snapshot_tree }) }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
      allow(subject).to receive(:find_vm).with(vmname,connection).and_return(vm_object)
    end

    context 'when VM does not exist' do
      before(:each) do
        expect(subject).to receive(:find_vm).with(vmname, connection).and_return(nil)
      end

      it 'should raise an error' do
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when snapshot already exists' do
      let(:snapshot_object) { mock_RbVmomi_VIM_VirtualMachineSnapshot() }
      let(:snapshot_tree) { { snapshot_name => { :ref => snapshot_object } } }

      it 'should raise an error' do
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Snapshot #{snapshot_name} .+ already exists /)
      end
    end

    context 'when snapshot raises an error' do
      before(:each) do
        expect(vm_object).to receive(:CreateSnapshot_Task).and_raise(RuntimeError,'Mock Snapshot Error')
      end

      it 'should raise an error' do
        expect{ subject.create_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Mock Snapshot Error/)
      end
    end

    context 'when snapshot succeeds' do
      before(:each) do
        expect(vm_object).to receive(:CreateSnapshot_Task)
          .with(create_snapshot_spec(snapshot_name))
          .and_return(snapshot_task)
        expect(snapshot_task).to receive(:wait_for_completion).and_return(nil)
      end

      it 'should return true' do
        expect(subject.create_snapshot(poolname,vmname,snapshot_name)).to be true
      end
    end
  end

  describe '#revert_snapshot' do
    let(:snapshot_task) { mock_RbVmomi_VIM_Task() }
    let(:snapshot_name) { 'snapshot' }
    let(:snapshot_tree) { { snapshot_name => { :ref => snapshot_object } } }
    let(:snapshot_object) { mock_RbVmomi_VIM_VirtualMachineSnapshot() }
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname, :snapshot_tree => snapshot_tree }) }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
      allow(subject).to receive(:find_vm).with(vmname,connection).and_return(vm_object)
    end

    context 'when VM does not exist' do
      before(:each) do
        expect(subject).to receive(:find_vm).with(vmname,connection).and_return(nil)
      end

      it 'should raise an error' do
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/VM #{vmname} .+ does not exist/)
      end
    end

    context 'when snapshot does not exist' do
      let(:snapshot_tree) {{}}

      it 'should raise an error' do
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Snapshot #{snapshot_name} .+ does not exist /)
      end
    end

    context 'when revert to snapshot raises an error' do
      before(:each) do
        expect(snapshot_object).to receive(:RevertToSnapshot_Task).and_raise(RuntimeError,'Mock Snapshot Error')
      end

      it 'should raise an error' do
        expect{ subject.revert_snapshot(poolname,vmname,snapshot_name) }.to raise_error(/Mock Snapshot Error/)
      end
    end

    context 'when revert to snapshot succeeds' do
      before(:each) do
        expect(snapshot_object).to receive(:RevertToSnapshot_Task).and_return(snapshot_task)
        expect(snapshot_task).to receive(:wait_for_completion).and_return(nil)
      end

      it 'should return true' do
        expect(subject.revert_snapshot(poolname,vmname,snapshot_name)).to be true
      end
    end
  end

  describe '#destroy_vm' do
    let(:power_off_task) { mock_RbVmomi_VIM_Task() }
    let(:destroy_task) { mock_RbVmomi_VIM_Task() }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    context 'Given a missing VM name' do
      before(:each) do
        expect(subject).to receive(:find_vm).and_return(nil)
      end

      it 'should return true' do
        expect(subject.destroy_vm(poolname, 'missing_vm')).to be true
      end
    end

    context 'Given a powered on VM' do
      let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({
          :name => vmname,
          :powerstate => 'poweredOn',
        })
      }

      before(:each) do
        expect(subject).to receive(:find_vm).and_return(vm_object)
        allow(vm_object).to receive(:PowerOffVM_Task).and_return(power_off_task)
        allow(vm_object).to receive(:Destroy_Task).and_return(destroy_task)

        allow(power_off_task).to receive(:wait_for_completion)
        allow(destroy_task).to receive(:wait_for_completion)
      end

      it 'should call PowerOffVM_Task on the VM' do
        expect(vm_object).to receive(:PowerOffVM_Task).and_return(power_off_task)

        subject.destroy_vm(poolname, vmname)
      end

      it 'should call Destroy_Task on the VM' do
        expect(vm_object).to receive(:Destroy_Task).and_return(destroy_task)

        subject.destroy_vm(poolname, vmname)
      end

      it 'should return true' do
        expect(subject.destroy_vm(poolname, vmname)).to be true
      end
    end

    context 'Given a powered off VM' do
      let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({
          :name => vmname,
          :powerstate => 'poweredOff',
        })
      }

      before(:each) do
        expect(subject).to receive(:find_vm).and_return(vm_object)
        allow(vm_object).to receive(:Destroy_Task).and_return(destroy_task)

        allow(destroy_task).to receive(:wait_for_completion)
      end

      it 'should not call PowerOffVM_Task on the VM' do
        expect(vm_object).to receive(:PowerOffVM_Task).exactly(0).times

        subject.destroy_vm(poolname, vmname)
      end

      it 'should call Destroy_Task on the VM' do
        expect(vm_object).to receive(:Destroy_Task).and_return(destroy_task)

        subject.destroy_vm(poolname, vmname)
      end

      it 'should return true' do
        expect(subject.destroy_vm(poolname, vmname)).to be true
      end
    end
  end

  describe '#vm_ready?' do
    context 'When a VM is ready' do
      before(:each) do
        expect(subject).to receive(:open_socket).with(vmname)
      end

      it 'should return true' do
        expect(subject.vm_ready?(poolname,vmname)).to be true
      end
    end

    context 'When a VM is ready but the pool does not exist' do
      # TODO not sure how to handle a VM that is passed in but
      # not located in the pool.  Is that ready or not?
      before(:each) do
        expect(subject).to receive(:open_socket).with(vmname)
      end

      it 'should return true' do
        expect(subject.vm_ready?('missing_pool',vmname)).to be true
      end
    end

    context 'When an error occurs connecting to the VM' do
      # TODO not sure how to handle a VM that is passed in but
      # not located in the pool.  Is that ready or not?
      before(:each) do
        expect(subject).to receive(:open_socket).and_raise(RuntimeError,'MockError')
      end

      it 'should return false' do
        expect(subject.vm_ready?(poolname,vmname)).to be false
      end
    end
  end

  describe '#vm_exists?' do
    it 'should return true when get_vm returns an object' do
      allow(subject).to receive(:get_vm).with(poolname,vmname).and_return(mock_RbVmomi_VIM_VirtualMachine({ :name => vmname }))

      expect(subject.vm_exists?(poolname,vmname)).to eq(true)
    end

    it 'should return false when get_vm returns nil' do
      allow(subject).to receive(:get_vm).with(poolname,vmname).and_return(nil)

      expect(subject.vm_exists?(poolname,vmname)).to eq(false)
    end
  end

  # vSphere helper methods
  describe '#get_target_datacenter_from_config' do
    let(:pool_dc) { 'PoolDC'}
    let(:provider_dc) { 'ProvDC'}

    context 'when not specified' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :vsphere:
    server: "vcenter.domain.local"
    username: "vcenter_user"
    password: "vcenter_password"
:pools:
  - name: '#{poolname}'
EOT
        )
      }
      it 'returns nil' do
        expect(subject.get_target_datacenter_from_config(poolname)).to be_nil
      end
    end

    context 'when specified only in the pool' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :vsphere:
    server: "vcenter.domain.local"
    username: "vcenter_user"
    password: "vcenter_password"
:pools:
  - name: '#{poolname}'
    datacenter: '#{pool_dc}'
EOT
        )
      }
      it 'returns the pool datacenter' do
        expect(subject.get_target_datacenter_from_config(poolname)).to eq(pool_dc)
      end
    end

    context 'when specified only in the provider' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :vsphere:
    server: "vcenter.domain.local"
    username: "vcenter_user"
    password: "vcenter_password"
    datacenter: '#{provider_dc}'
:pools:
  - name: '#{poolname}'
EOT
        )
      }
      it 'returns the provider datacenter' do
        expect(subject.get_target_datacenter_from_config(poolname)).to eq(provider_dc)
      end
    end

    context 'when specified in the provider and pool' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :vsphere:
    server: "vcenter.domain.local"
    username: "vcenter_user"
    password: "vcenter_password"
    datacenter: '#{provider_dc}'
:pools:
  - name: '#{poolname}'
    datacenter: '#{pool_dc}'
EOT
        )
      }
      it 'returns the pool datacenter' do
        expect(subject.get_target_datacenter_from_config(poolname)).to eq(pool_dc)
      end
    end
  end

  # vSphere helper methods
  describe '#ensured_vsphere_connection' do
    let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :vsphere:
    # Drop the connection pool timeout way down for spec tests so they fail fast
    connection_pool_timeout: 1
    connection_pool_size: 1
:pools:
EOT
      )
    }
    let(:connection1) { mock_RbVmomi_VIM_Connection(connection_options) }
    let(:connection2) { mock_RbVmomi_VIM_Connection(connection_options) }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection1)
    end

    # This is to ensure that the pool_size of 1 is in effect
    it 'should return the same connection object when calling the pool multiple times' do
      subject.connection_pool.with_metrics do |pool_object|
        expect(pool_object[:connection]).to be(connection1)
      end
      subject.connection_pool.with_metrics do |pool_object|
        expect(pool_object[:connection]).to be(connection1)
      end
      subject.connection_pool.with_metrics do |pool_object|
        expect(pool_object[:connection]).to be(connection1)
      end
    end

    context 'when the connection breaks' do
      before(:each) do
        # Emulate the connection state being good, then bad, then good again
        expect(subject).to receive(:vsphere_connection_ok?).and_return(true, false, true)
        expect(subject).to receive(:connect_to_vsphere).and_return(connection1, connection2)
      end

      it 'should restore the connection' do
        subject.connection_pool.with_metrics do |pool_object|
          # This line needs to be added to all instances of the connection_pool allocation
          connection = subject.ensured_vsphere_connection(pool_object)

          expect(connection).to be(connection1)
        end

        subject.connection_pool.with_metrics do |pool_object|
          connection = subject.ensured_vsphere_connection(pool_object)
          # The second connection would have failed.  This test ensures that a
          # new connection object was created.
          expect(connection).to be(connection2)
        end

        subject.connection_pool.with_metrics do |pool_object|
          connection = subject.ensured_vsphere_connection(pool_object)
          expect(connection).to be(connection2)
        end
      end
    end
  end

  describe '#connect_to_vsphere' do
    before(:each) do
      allow(RbVmomi::VIM).to receive(:connect).and_return(connection)
    end

    let (:credentials) { config[:providers][:vsphere] }

    context 'succesful connection' do
      it 'should use the supplied credentials' do
        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => credentials['insecure']
        }).and_return(connection)
        subject.connect_to_vsphere
      end

      it 'should honor the insecure setting' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/207')
        config[:providers][:vsphere][:insecure] = false

        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => false,
        }).and_return(connection)
        subject.connect_to_vsphere
      end

      it 'should default to an insecure connection' do
        config[:providers][:vsphere][:insecure] = nil

        expect(RbVmomi::VIM).to receive(:connect).with({
          :host     => credentials['server'],
          :user     => credentials['username'],
          :password => credentials['password'],
          :insecure => true
        }).and_return(connection)

        subject.connect_to_vsphere
      end

      it 'should return the connection object' do
        result = subject.connect_to_vsphere

        expect(result).to be(connection)
      end

      it 'should increment the connect.open counter' do
        expect(metrics).to receive(:increment).with('connect.open')
        subject.connect_to_vsphere
      end
    end

    context 'connection is initially unsuccessful' do
      before(:each) do
        # Simulate a failure and then success
        expect(RbVmomi::VIM).to receive(:connect).and_raise(RuntimeError,'MockError').ordered
        expect(RbVmomi::VIM).to receive(:connect).and_return(connection).ordered

        allow(subject).to receive(:sleep)
      end

      it 'should return the connection object' do
        result = subject.connect_to_vsphere

        expect(result).to be(connection)
      end

      it 'should increment the connect.fail and then connect.open counter' do
        expect(metrics).to receive(:increment).with('connect.fail').exactly(1).times
        expect(metrics).to receive(:increment).with('connect.open').exactly(1).times
        subject.connect_to_vsphere
      end
    end

    context 'connection is always unsuccessful' do
      before(:each) do
        allow(RbVmomi::VIM).to receive(:connect).and_raise(RuntimeError,'MockError')
        allow(subject).to receive(:sleep)
      end

      it 'should raise an error' do
        expect{subject.connect_to_vsphere}.to raise_error(RuntimeError,'MockError')
      end

      it 'should retry the connection attempt config.max_tries times' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/199')
        expect(RbVmomi::VIM).to receive(:connect).exactly(config[:config]['max_tries']).times.and_raise(RuntimeError,'MockError')

        begin
          # Swallow any errors
          subject.connect_to_vsphere
        rescue
        end
      end

      it 'should increment the connect.fail counter config.max_tries times' do
        pending('Resolution of issue https://github.com/puppetlabs/vmpooler/issues/199')
        expect(metrics).to receive(:increment).with('connect.fail').exactly(config[:config]['max_tries']).times

        begin
          # Swallow any errors
          subject.connect_to_vsphere
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
              subject.connect_to_vsphere
            rescue
            end
          end
        end
      end
    end
  end

  describe '#open_socket' do
    let(:TCPSocket) { double('tcpsocket') }
    let(:socket) { double('tcpsocket') }
    let(:hostname) { 'host' }
    let(:domain) { 'domain.local'}
    let(:default_socket) { 22 }

    before do
      expect(subject).not_to be_nil
      allow(socket).to receive(:close)
    end

    it 'opens socket with defaults' do
      expect(TCPSocket).to receive(:new).with(hostname,default_socket).and_return(socket)

      expect(subject.open_socket(hostname)).to eq(nil)
    end

    it 'yields the socket if a block is given' do
      expect(TCPSocket).to receive(:new).with(hostname,default_socket).and_return(socket)

      expect{ |socket| subject.open_socket(hostname,nil,nil,default_socket,&socket) }.to yield_control.exactly(1).times 
    end

    it 'closes the opened socket' do
      expect(TCPSocket).to receive(:new).with(hostname,default_socket).and_return(socket)
      expect(socket).to receive(:close)

      expect(subject.open_socket(hostname)).to eq(nil)
    end

    it 'opens a specific socket' do
      expect(TCPSocket).to receive(:new).with(hostname,80).and_return(socket)

      expect(subject.open_socket(hostname,nil,nil,80)).to eq(nil)
    end

    it 'uses a specific domain with the hostname' do
      expect(TCPSocket).to receive(:new).with("#{hostname}.#{domain}",default_socket).and_return(socket)

      expect(subject.open_socket(hostname,domain)).to eq(nil)
    end

    it 'raises error if host is not resolvable' do
      expect(TCPSocket).to receive(:new).with(hostname,default_socket).and_raise(SocketError,'getaddrinfo: No such host is known')

      expect { subject.open_socket(hostname,nil,1) }.to raise_error(SocketError)
    end

    it 'raises error if socket is not listening' do
      expect(TCPSocket).to receive(:new).with(hostname,default_socket).and_raise(SocketError,'No connection could be made because the target machine actively refused it')

      expect { subject.open_socket(hostname,nil,1) }.to raise_error(SocketError)
    end
  end

  describe '#get_vm_folder_path' do
    [
      { :path_description => 'Datacenters/DC01/vm/Pooler/pool1/vm1',
        :expected_path => 'Pooler/pool1',
        :vm_object_path => [
          { :type => 'folder',     :name => 'Datacenters' },
          { :type => 'datacenter', :name => 'DC01' },
          { :type => 'folder',     :name => 'vm' },
          { :type => 'folder',     :name => 'Pooler' },
          { :type => 'folder',     :name => 'pool1'},
        ],
      },
      { :path_description => 'Datacenters/DC01/vm/something/subfolder/pool/vm1',
        :expected_path => 'something/subfolder/pool',
        :vm_object_path => [
          { :type => 'folder',     :name => 'Datacenters' },
          { :type => 'datacenter', :name => 'DC01' },
          { :type => 'folder',     :name => 'vm' },
          { :type => 'folder',     :name => 'something' },
          { :type => 'folder',     :name => 'subfolder' },
          { :type => 'folder',     :name => 'pool'},
        ],
      },
      { :path_description => 'Datacenters/DC01/vm/vm1',
        :expected_path => '',
        :vm_object_path => [
          { :type => 'folder',     :name => 'Datacenters' },
          { :type => 'datacenter', :name => 'DC01' },
          { :type => 'folder',     :name => 'vm' },
        ],
      },
    ].each do |testcase|
      context "given a path of #{testcase[:path_description]}" do
        it "should return '#{testcase[:expected_path]}'" do
          vm_object = mock_RbVmomi_VIM_VirtualMachine({
            :name => 'vm1',
            :path => testcase[:vm_object_path],
          })
          expect(subject.get_vm_folder_path(vm_object)).to eq(testcase[:expected_path])
        end
      end
    end

    [
      { :path_description => 'a path missing a Datacenter',
        :vm_object_path => [
          { :type => 'folder',     :name => 'Datacenters' },
          { :type => 'folder',     :name => 'vm' },
          { :type => 'folder',     :name => 'Pooler' },
          { :type => 'folder',     :name => 'pool1'},
        ],
      },
      { :path_description => 'a path missing root VM folder',
        :vm_object_path => [
          { :type => 'folder',     :name => 'Datacenters' },
          { :type => 'datacenter', :name => 'DC01' },
        ],
      },
    ].each do |testcase|
      context "given #{testcase[:path_description]}" do
        it "should return nil" do
          vm_object = mock_RbVmomi_VIM_VirtualMachine({
            :name => 'vm1',
            :path => testcase[:vm_object_path],
          })
          expect(subject.get_vm_folder_path(vm_object)).to be_nil
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

    # Require at least one DC with the required datastore
    let(:connection_options) {{
      :serviceContent => {
        :datacenters => [
          { :name => datacenter_name, :datastores => [datastorename] }
        ]
      }
    }}

    let(:create_virtual_disk_task) { mock_RbVmomi_VIM_Task() }
    let(:reconfig_vm_task) { mock_RbVmomi_VIM_Task() }

    before(:each) do
      # Mocking for find_vmdks
      allow(connection.serviceContent.propertyCollector).to receive(:collectMultiple).and_return(collectMultiple_response)

      # Mocking for creating the disk
      allow(connection.serviceContent.virtualDiskManager).to receive(:CreateVirtualDisk_Task) do |options|
        if options[:datacenter][:name] == datacenter_name
          create_virtual_disk_task
        end
      end
      allow(create_virtual_disk_task).to receive(:wait_for_completion).and_return(true)

      # Mocking for adding disk to the VM
      allow(vm_object).to receive(:ReconfigVM_Task).and_return(reconfig_vm_task)
      allow(reconfig_vm_task).to receive(:wait_for_completion).and_return(true)
    end

    context 'Succesfully addding disk' do
      it 'should return true' do
        expect(subject.add_disk(vm_object,disk_size,datastorename,connection,datacenter_name)).to be true
      end

      it 'should request a disk of appropriate size' do
        expect(connection.serviceContent.virtualDiskManager).to receive(:CreateVirtualDisk_Task)
          .with(create_virtual_disk_with_size(disk_size))
          .and_return(create_virtual_disk_task)


        subject.add_disk(vm_object,disk_size,datastorename,connection,datacenter_name)
      end
    end

    context 'Requested disk size is 0' do
      it 'should raise an error' do
        expect(subject.add_disk(vm_object,0,datastorename,connection,datacenter_name)).to be false
      end
    end

    context 'No datastores or datastore missing' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name, :datastores => ['missing_datastore'] }
          ]
        }
      }}

      it 'should raise error' do
        expect{ subject.add_disk(vm_object,disk_size,datastorename,connection,datacenter_name) }.to raise_error(/does not exist/)
      end
    end

    context 'Multiple datacenters with multiple datastores' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'AnotherDC', :datastores => ['dc1','dc2'] },
            { :name => datacenter_name, :datastores => ['dc3',datastorename,'dc4'] },
          ]
        }
      }}

      it 'should return true' do
        expect(subject.add_disk(vm_object,disk_size,datastorename,connection,datacenter_name)).to be true
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
        expect{ subject.add_disk(vm_object,disk_size,datastorename,connection,datacenter_name) }.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_datastore' do
    let(:datastorename) { 'datastore' }
    let(:datastore_list) { [] }

    context 'No datastores in the datacenter' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name, :datastores => [] }
          ]
        }
      }}

      it 'should return nil if the datastore is not found' do
        result = subject.find_datastore(datastorename,connection,datacenter_name)
        expect(result).to be_nil
      end
    end

    context 'Many datastores in the datacenter' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name, :datastores => ['ds1','ds2',datastorename,'ds3'] }
          ]
        }
      }}

      it 'should return nil if the datastore is not found' do
        result = subject.find_datastore('missing_datastore',connection,datacenter_name)
        expect(result).to be_nil
      end

      it 'should find the datastore in the datacenter' do
        result = subject.find_datastore(datastorename,connection,datacenter_name)
        
        expect(result).to_not be_nil
        expect(result.is_a?(RbVmomi::VIM::Datastore)).to be true
        expect(result.name).to eq(datastorename)
      end
    end

    context 'Many datastores in many datacenters' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'AnotherDC', :datastores => ['ds1','ds2','ds3'] },
            { :name => datacenter_name, :datastores => ['ds3','ds4',datastorename,'ds5'] },
          ]
        }
      }}

      it 'should return nil if the datastore is not found' do
        result = subject.find_datastore(datastorename,connection,'AnotherDC')
        expect(result).to be_nil
      end

      it 'should find the datastore in the datacenter' do
        result = subject.find_datastore(datastorename,connection,datacenter_name)
        
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

    context 'with no folder hierarchy' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name }
          ]
        }
      }}

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername,connection,datacenter_name)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
              :vmfolder_tree => {
                'folder1' => nil,
                'folder2' => nil,
                foldername => nil,
                'folder3' => nil,
              }
            }
          ]
        }
      }}

      it 'should return the folder when found' do
        result = subject.find_folder(foldername,connection,datacenter_name)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername,connection,datacenter_name)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy in many datacenters' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'AnotherDC',
              :vmfolder_tree => {
                'folder1' => nil,
                'folder2' => nil,
                'folder3' => nil,
              }
            },
            { :name => datacenter_name,
              :vmfolder_tree => {
                'folder4' => nil,
                'folder5' => nil,
                foldername => nil,
                'folder6' => nil,
              }
            }
          ]
        }
      }}

      it 'should return the folder when found' do
        result = subject.find_folder(foldername,connection,datacenter_name)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername,connection,'AnotherDC')).to be_nil
      end
    end

    context 'with a VM with the same name as a folder in a single layer folder hierarchy' do
      # The folder hierarchy should include a VM with same name as folder, and appear BEFORE the
      # folder in the child list.
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
              :vmfolder_tree => {
                'folder1' => nil,
                'vm1' => { :object_type => 'vm', :name => foldername },
                foldername => nil,
                'folder3' => nil,
              }
            }
          ]
        }
      }}

      it 'should not return a VM' do
        pending('https://github.com/puppetlabs/vmpooler/issues/204')
        result = subject.find_folder(foldername,connection,datacenter_name)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
        expect(result.is_a? RbVmomi::VIM::VirtualMachine).to be false
      end
    end

    context 'with a multi layer folder hierarchy' do
      let(:end_folder_name) { 'folder'}
      let(:foldername) { 'folder2/folder4/' + end_folder_name}
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
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
            }
          ]
        }
      }}

      it 'should return the folder when found' do
        result = subject.find_folder(foldername,connection,datacenter_name)
        expect(result).to_not be_nil
        expect(result.name).to eq(end_folder_name)
      end

      it 'should return nil if the folder is not found' do
        expect(subject.find_folder(missing_foldername,connection,datacenter_name)).to be_nil
      end
    end

    context 'with a VM with the same name as a folder in a multi layer folder hierarchy' do
      # The folder hierarchy should include a VM with same name as folder mid-hierarchy (i.e. not at the end level)
      # and appear BEFORE the folder in the child list.
      let(:end_folder_name) { 'folder'}
      let(:foldername) { 'folder2/folder4/' + end_folder_name}
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
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
            }
          ]
        }
      }}

      it 'should not return a VM' do
        pending('https://github.com/puppetlabs/vmpooler/issues/204')
        result = subject.find_folder(foldername,connection,datacenter_name)
        expect(result).to_not be_nil
        expect(result.name).to eq(foldername)
        expect(result.is_a? RbVmomi::VIM::VirtualMachine,datacenter_name).to be false
      end
    end
  end

  describe '#get_host_utilization' do
    let(:cpu_model) { 'vendor line type sku v4 speed' }
    let(:model) { 'v4' }
    let(:different_model) { 'different_model' }
    let(:limit) { 75 }
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

    context "host with configuration issue" do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
        :config_issue => 'No quickstats',
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
        expect(subject.get_host_utilization(host,model,limit)[0]).to eq(10)
      end

      it 'should return the host' do
        expect(subject.get_host_utilization(host,model,limit)[1]).to eq(host)
      end
    end

    context 'host with no quickstats' do
      let(:host) { mock_RbVmomi_VIM_HostSystem({
        :cpu_speed => 100,
        :num_cores_per_cpu => 1,
        :num_cpu => 1,
        :memory_size => 100.0 * 1024 * 1024
        })
      }
      before(:each) do
        host.summary.quickStats.overallCpuUsage = nil
      end

      it 'should return nil' do
        result = subject.get_host_utilization(host,model,limit)
        expect(result).to be nil
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

  describe '#select_target_hosts' do
    let(:target) { {} }
    let(:cluster) { 'cluster1' }
    let(:missing_cluster_name) { 'missing_cluster' }
    let(:datacenter) { 'dc1' }
    let(:architecture) { 'v3' }
    let(:host) { 'host1' }
    let(:hosts_hash) {
      {
        'hosts' => [host],
        'architectures' => {
          architecture => [host]
        }
      }
    }

    it 'returns a hash of the least used hosts by cluster and architecture' do
      expect(subject).to receive(:find_least_used_hosts).and_return(hosts_hash)

      subject.select_target_hosts(target, cluster, datacenter)
      expect(target["#{datacenter}_#{cluster}"]).to eq(hosts_hash)
    end

    context 'with a cluster specified that does not exist' do
      it 'raises an error' do
        expect(subject).to receive(:find_least_used_hosts).with(missing_cluster_name, datacenter, 100).and_raise("Cluster #{cluster} cannot be found")
        expect{subject.select_target_hosts(target, missing_cluster_name, datacenter)}.to raise_error(RuntimeError,/Cluster #{cluster} cannot be found/)
      end
    end
  end

  describe '#get_average_cluster_utilization' do
    let(:hosts) {
      [
        [60, 'host1'],
        [100, 'host2'],
        [200, 'host3']
      ]
    }
    it 'returns the average utilization for a given set of host utilizations assuming the first member of the list for each host is the utilization value' do
      expect(subject.get_average_cluster_utilization(hosts)).to eq(120)
    end
  end

  describe '#build_compatible_hosts_lists' do
    let(:host1) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST1' })}
    let(:host2) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST2' })}
    let(:host3) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST3' })}
    let(:architecture) { 'v4' }
    let(:percentage) { 100 }
    let(:hosts) {
      [
        [60, host1],
        [100, host2],
        [200, host3]
      ]
    }
    let(:result) {
      {
          architecture => ['HOST1','HOST2']
      }
    }

    it 'returns a hash of target host architecture versions containing lists of target hosts' do

      expect(subject.build_compatible_hosts_lists(hosts, percentage)).to eq(result)
    end
  end

  describe '#select_least_used_hosts' do
    let(:percentage) { 100 }
    let(:host1) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST1' })}
    let(:host2) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST2' })}
    let(:host3) { mock_RbVmomi_VIM_HostSystem({ :name => 'HOST3' })}
    let(:hosts) {
      [
        [60, host1],
        [100, host2],
        [200, host3]
      ]
    }
    let(:result) { ['HOST1','HOST2'] }
    it 'returns the percentage specified of the least used hosts in the cluster determined by selecting from less than or equal to average cluster utilization' do
      expect(subject.select_least_used_hosts(hosts, percentage)).to eq(result)
    end

    context 'when selecting 20 percent of hosts below average' do
      let(:percentage) { 20 }
      let(:result) { ['HOST1'] }

      it 'should return the result' do
        expect(subject.select_least_used_hosts(hosts, percentage)).to eq(result)
      end
    end

    it 'should raise' do
      expect{subject.select_least_used_hosts([], percentage)}.to raise_error(RuntimeError,/Provided hosts list to select_least_used_hosts is empty/)
    end
  end

  describe '#run_select_hosts' do
    let(:target) { {} }
    let(:cluster) { 'cluster1' }
    let(:missing_cluster_name) { 'missing_cluster' }
    let(:datacenter) { 'dc1' }
    let(:architecture) { 'v3' }
    let(:host) { 'host1' }
    let(:loop_delay) { 5 }
    let(:max_age) { 60 }
    let(:dc) { "#{datacenter}_#{cluster}" }
    let(:hosts_hash) {
      {
       dc => {
          'hosts' => [host],
          'architectures' => {
            architecture => [host]
          }
        }
      }
    }
    let(:config) { YAML.load(<<-EOT
---
:config:
  max_age: 60
:pools:
  - name: '#{poolname}'
    datacenter: '#{datacenter}'
    clone_target: '#{cluster}'
EOT
      )
    }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    context 'target does not have key dc' do
      let(:hosts_hash) { { } }
      it 'should run select_target_hosts' do
        expect(subject).to receive(:select_target_hosts).with(hosts_hash, cluster, datacenter)
        subject.run_select_hosts(poolname, hosts_hash)
      end
    end

    context 'when check_time_finished is greater than max_age' do
      before(:each) do
        hosts_hash[dc]['check_time_finished'] = Time.now - (max_age + 10)
      end

      it 'should run select_target_hosts' do
        expect(subject).to receive(:select_target_hosts).with(hosts_hash, cluster, datacenter)
        subject.run_select_hosts(poolname, hosts_hash)
      end
    end

    context 'when check_time_finished is not greater than max_age' do
      before(:each) do
        hosts_hash[dc]['check_time_finished'] = Time.now - (max_age / 2)
      end

      it 'should not run select_target_hosts' do
        expect(subject).to_not receive(:select_target_hosts).with(hosts_hash, cluster, datacenter)
        subject.run_select_hosts(poolname, hosts_hash)
      end
    end

    context 'when hosts are being selected' do
      before(:each) do
        hosts_hash[dc]['checking'] = true
      end

      it 'should run wait_for_host_selection' do
        expect(subject).to receive(:wait_for_host_selection).with(dc, hosts_hash, loop_delay, max_age)
        subject.run_select_hosts(poolname, hosts_hash)
      end

    end

    context 'with no clone_target' do
      before(:each) do
        config[:pools][0].delete('clone_target')
      end

      it 'should raise an error' do
        expect{subject.run_select_hosts(poolname, hosts_hash)}.to raise_error(/cluster for pool #{poolname} cannot be identified/)
      end
    end

    context 'with no datacenter' do
      before(:each) do
        config[:pools][0].delete('datacenter')
      end

      it 'should raise an error' do
        expect{subject.run_select_hosts(poolname, hosts_hash)}.to raise_error(/datacenter for pool #{poolname} cannot be identified/)
      end
    end
  end

  describe '#wait_for_host_selection' do
    let(:datacenter) { 'dc1' }
    let(:cluster) { 'cluster1' }
    let(:dc) { "#{datacenter}_#{cluster}" }
    let(:maxloop) { 1 }
    let(:loop_delay) { 1 }
    let(:max_age) { 60 }
    let(:target) {
      {
        dc => { }
      }
    }

    context 'when target does not have key check_time_finished' do
      it 'should sleep for loop_delay maxloop times' do
        expect(subject).to receive(:sleep).with(loop_delay).once

        subject.wait_for_host_selection(dc, target, maxloop, loop_delay, max_age)
      end
    end

    context 'when target has dc and check_time_finished is greater than max_age' do
      before(:each) do
        target[dc]['check_time_finished'] = Time.now - (max_age + 10)
      end

      it 'should sleep for loop_delay maxloop times' do
        expect(subject).to receive(:sleep).with(loop_delay).once

        subject.wait_for_host_selection(dc, target, maxloop, loop_delay, max_age)
      end
    end

    context 'when target has dc and check_time_finished difference from now is less than max_age' do
      before(:each) do
        target[dc]['check_time_finished'] = Time.now - (max_age / 2)
      end

      it 'should not wait' do
        expect(subject).to_not receive(:sleep).with(loop_delay)

        subject.wait_for_host_selection(dc, target, maxloop, loop_delay, max_age)
      end
    end
  end

  describe '#select_next_host' do
    let(:cluster) { 'cluster1' }
    let(:datacenter) { 'dc1' }
    let(:architecture) { 'v3' }
    let(:host) { 'host1' }
    let(:loop_delay) { 5 }
    let(:max_age) { 60 }
    let(:dc) { "#{datacenter}_#{cluster}" }
    let(:hosts_hash) {
      {
       dc => {
          'hosts' => [host, 'host2'],
          'architectures' => {
            architecture => ['host3', 'host4']
          }
        }
      }
    }
    let(:config) { YAML.load(<<-EOT
---
:config:
  max_age: 60
:pools:
  - name: '#{poolname}'
    datacenter: '#{datacenter}'
    clone_target: '#{cluster}'
EOT
      )
    }

    context 'when host is requested' do
      it 'should return the first host' do
        result = subject.select_next_host(poolname, hosts_hash)
        expect(result).to eq(host)
      end

      it 'should return the second host if called twice' do
        result = subject.select_next_host(poolname, hosts_hash)
        result2 = subject.select_next_host(poolname, hosts_hash)
        expect(result2).to eq('host2')
      end
    end

    context 'when host and architecture are requested' do
      it 'should return the first host' do
        result = subject.select_next_host(poolname, hosts_hash, architecture)
        expect(result).to eq('host3')
      end

      it 'should return the second host if called twice' do
        result = subject.select_next_host(poolname, hosts_hash, architecture)
        result2 = subject.select_next_host(poolname, hosts_hash, architecture)
        expect(result2).to eq('host4')
      end
    end

    context 'with no hosts available' do
      before(:each) do
        hosts_hash[dc].delete('hosts')
        hosts_hash[dc].delete('architectures')
      end
      it 'should raise an error' do
        expect{subject.select_next_host(poolname, hosts_hash)}.to raise_error("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory")
      end

      it 'should raise an error when selecting with architecture' do
        expect{subject.select_next_host(poolname, hosts_hash, architecture)}.to raise_error("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory")
      end
    end

    context 'with no datacenter set for pool' do
      before(:each) do
        config[:pools][0].delete('datacenter')
      end

      it 'should raise an error' do
        expect{subject.select_next_host(poolname, hosts_hash)}.to raise_error("datacenter for pool #{poolname} cannot be identified")
      end
    end

    context 'with no clone_target set for pool' do
      before(:each) do
        config[:pools][0].delete('clone_target')
      end

      it 'should raise an error' do
        expect{subject.select_next_host(poolname, hosts_hash)}.to raise_error("cluster for pool #{poolname} cannot be identified")
      end
    end
  end

  describe '#vm_in_target?' do
    let(:parent_host) { 'host1' }
    let(:architecture) { 'v3' }
    let(:datacenter) { 'dc1' }
    let(:cluster) { 'cluster1' }
    let(:dc) { "#{datacenter}_#{cluster}" }
    let(:maxloop) { 1 }
    let(:loop_delay) { 1 }
    let(:max_age) { 60 }
    let(:target) {
      {
        dc => {
          'hosts' => [parent_host],
          'architectures' => {
            architecture => [parent_host]
          }
        }
      }
    }
    let(:config) { YAML.load(<<-EOT
---
:pools:
  - name: '#{poolname}'
    datacenter: '#{datacenter}'
    clone_target: '#{cluster}'
EOT
      )
    }

    it 'returns true when parent_host is in hosts' do
      result = subject.vm_in_target?(poolname, parent_host, architecture, target)
      expect(result).to be true
    end

    context 'with parent_host only in architectures' do
      before(:each) do
        target[dc]['hosts'] = ['host2']
      end

      it 'returns true when parent_host is in architectures' do
        result = subject.vm_in_target?(poolname, parent_host, architecture, target)
        expect(result).to be true
      end
    end

    it 'returns false when parent_host is not in hosts or architectures' do
      result = subject.vm_in_target?(poolname, 'host3', architecture, target)
      expect(result).to be false
    end

    context 'with no hosts key' do
      before(:each) do
        target[dc].delete('hosts')
      end

      it 'should raise an error' do
        expect{subject.vm_in_target?(poolname, parent_host, architecture, target)}.to raise_error("there is no candidate in vcenter that meets all the required conditions, that the cluster has available hosts in a 'green' status, not in maintenance mode and not overloaded CPU and memory")
      end
    end
  end

  describe '#get_vm_details' do
    let(:parent_host) { 'host1' }
    let(:host_object) { mock_RbVmomi_VIM_HostSystem({ :name => parent_host })}
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
    let(:architecture) { 'v4' }
    let(:vm_details) {
      {
        'host_name' => parent_host,
        'object' => vm_object,
        'architecture' => architecture
      }
    }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    it 'returns nil when vm_object is not found' do
      expect(subject).to receive(:find_vm).with(vmname, connection).and_return(nil)
      result = subject.get_vm_details(vmname, connection)
      expect(result).to be nil
    end

    it 'raises an error when unable to determine parent_host' do
      expect(subject).to receive(:find_vm).with(vmname, connection).and_return(vm_object)
      expect{subject.get_vm_details(vmname, connection)}.to raise_error('Unable to determine which host the VM is running on')
    end

    context 'when it can find parent host' do
      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm_object.summary.runtime.host = host_object
      end

      it 'returns vm details hash' do
        expect(subject).to receive(:find_vm).with(vmname, connection).and_return(vm_object)
        result = subject.get_vm_details(vmname, connection)
        expect(result).to eq(vm_details)
      end
    end
  end

  describe '#migrate_vm' do
    let(:parent_host) { 'host1' }
    let(:new_host) { 'host2' }
    let(:datacenter) { 'dc1' }
    let(:architecture) { 'v4' }
    let(:cluster) { 'cluster1' }
    let(:vm_details) {
      {
        'host_name' => parent_host,
        'object' => vm_object,
        'architecture' => architecture
      }
    }
    let(:host_object) { mock_RbVmomi_VIM_HostSystem({ :name => parent_host })}
    let(:new_host_object) { mock_RbVmomi_VIM_HostSystem({ :name => new_host })}
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
    let(:config) { YAML.load(<<-EOT
---
:config:
  migration_limit: 5
:pools:
  - name: '#{poolname}'
    datacenter: '#{datacenter}'
    clone_target: '#{cluster}'
EOT
      )
    }
    let(:dc) { "#{datacenter}_#{cluster}" }
    let(:provider_hosts) {
      {
        dc => {
          'hosts' => [new_host],
          'architectures' => {
            architecture => [new_host]
          },
          'check_time_finished' => Time.now
        }
      }
    }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    context 'when vm should be migrated' do
      before(:each) do
        subject.connection_pool.with_metrics do |pool_object|
          expect(subject).to receive(:ensured_vsphere_connection).with(pool_object).and_return(connection)
          expect(subject).to receive(:get_vm_details).and_return(vm_details)
          expect(subject).to receive(:run_select_hosts).with(poolname, {})
          expect(subject).to receive(:vm_in_target?).and_return false
          expect(subject).to receive(:migration_enabled?).and_return true
        end
        vm_object.summary.runtime.host = host_object
      end

      it 'logs a message' do
        expect(subject).to receive(:select_next_host).and_return(new_host)
        expect(subject).to receive(:find_host_by_dnsname).and_return(new_host_object)
        expect(subject).to receive(:migrate_vm_host).with(vm_object, new_host_object)
        expect($redis).to receive(:hget).with("vmpooler__vm__#{vmname}", 'checkout').and_return((Time.now - 1).to_s)
        expect(logger).to receive(:log).with('s', "[>] [#{poolname}] '#{vmname}' migrated from #{parent_host} to #{new_host} in 0.00 seconds")

        subject.migrate_vm(poolname, vmname)
      end

      it 'migrates a vm' do
        expect(subject).to receive(:migrate_vm_to_new_host).with(poolname, vmname, vm_details, connection)

        subject.migrate_vm(poolname, vmname)
      end
    end

    context 'current host is in the list of target hosts' do
      before(:each) do
        subject.connection_pool.with_metrics do |pool_object|
          expect(subject).to receive(:ensured_vsphere_connection).with(pool_object).and_return(connection)
          expect(subject).to receive(:get_vm_details).and_return(vm_details)
          expect(subject).to receive(:run_select_hosts).with(poolname, {})
          expect(subject).to receive(:vm_in_target?).and_return true
          expect(subject).to receive(:migration_enabled?).and_return true
        end
        vm_object.summary.runtime.host = host_object
      end

      it 'logs a message that no migration is required' do
        expect(logger).to receive(:log).with('s', "[ ] [#{poolname}] No migration required for '#{vmname}' running on #{parent_host}")

        subject.migrate_vm(poolname, vmname)
      end
    end

    context 'with migration limit exceeded' do
      before(:each) do
        subject.connection_pool.with_metrics do |pool_object|
          expect(subject).to receive(:ensured_vsphere_connection).with(pool_object).and_return(connection)
          expect($redis).to receive(:scard).with('vmpooler__migration').and_return(5)
          expect(subject).to receive(:get_vm_details).and_return(vm_details)
          expect(subject).to_not receive(:run_select_hosts)
          expect(subject).to_not receive(:vm_in_target?)
          expect(subject).to receive(:migration_enabled?).and_return true
        end
        vm_object.summary.runtime.host = host_object
      end

      it 'should log the current host' do
        expect(logger).to receive(:log).with('s', "[ ] [#{poolname}] '#{vmname}' is running on #{parent_host}. No migration will be evaluated since the migration_limit has been reached")

        subject.migrate_vm(poolname, vmname)
      end
    end

    context 'when an error occurs' do
      before(:each) do
        subject.connection_pool.with_metrics do |pool_object|
          expect(subject).to receive(:ensured_vsphere_connection).with(pool_object).and_return(connection)
          expect(subject).to receive(:get_vm_details).and_return(vm_details)
          expect(subject).to receive(:run_select_hosts)
          expect(subject).to receive(:vm_in_target?).and_return false
          expect(subject).to receive(:migration_enabled?).and_return true
          expect(subject).to receive(:select_next_host).and_raise(RuntimeError,'Mock migration error')
        end
        vm_object.summary.runtime.host = host_object
      end
      it 'should log the current host' do
        expect(logger).to receive(:log).with('s', "[!] [#{poolname}] '#{vmname}' is running on #{parent_host}")

        expect{subject.migrate_vm(poolname, vmname)}.to raise_error(RuntimeError, 'Mock migration error')
      end
    end
  end

  describe '#migrate_vm_to_new_host' do
    let(:parent_host) { 'host1' }
    let(:new_host) { 'host2' }
    let(:datacenter) { 'dc1' }
    let(:cluster) { 'cluster1' }
    let(:architecture) { 'v4' }
    let(:host_object) { mock_RbVmomi_VIM_HostSystem({ :name => parent_host })}
    let(:new_host_object) { mock_RbVmomi_VIM_HostSystem({ :name => new_host })}
    let(:vm_object) { mock_RbVmomi_VIM_VirtualMachine({ :name => vmname })}
    let(:config) { YAML.load(<<-EOT
---
:config:
  migration_limit: 5
:pools:
  - name: '#{poolname}'
    datacenter: '#{datacenter}'
    clone_target: '#{cluster}'
EOT
      )
    }
    let(:vm_details) {
      {
        'host_name' => parent_host,
        'object' => vm_object,
        'architecture' => architecture
      }
    }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    it' migrates a vm' do
      expect($redis).to receive(:sadd).with('vmpooler__migration', vmname)
      expect(subject).to receive(:select_next_host).and_return(new_host)
      expect(subject).to receive(:find_host_by_dnsname).and_return(new_host_object)
      expect(subject).to receive(:migrate_vm_and_record_timing).and_return(format('%.2f', (Time.now - (Time.now - 15))))
      expect(logger).to receive(:log).with('s', "[>] [#{poolname}] '#{vmname}' migrated from host1 to host2 in 15.00 seconds")
      expect($redis).to receive(:srem).with('vmpooler__migration', vmname)
      subject.migrate_vm_to_new_host(poolname, vmname, vm_details, connection)
    end
  end

  describe '#create_folder' do
    let(:datacenter) { 'dc1' }
    let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }
    let(:folder_object) { mock_RbVmomi_VIM_Folder({ :name => 'pool1'}) }
    let(:new_folder) { poolname }

    before(:each) do
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
    end

    it 'creates a folder' do
      expect(connection.serviceInstance).to receive(:find_datacenter).with(datacenter).and_return(datacenter_object)
      expect(datacenter_object.vmFolder).to receive(:traverse).with(new_folder, type=RbVmomi::VIM::Folder, create=true).and_return(folder_object)

      result = subject.create_folder(connection, new_folder, datacenter)
      expect(result).to eq(folder_object)
    end

    context 'with folder_object returning nil' do
      it 'shoud raise an error' do
        expect(connection.serviceInstance).to receive(:find_datacenter).with(datacenter).and_return(datacenter_object)
        expect(datacenter_object.vmFolder).to receive(:traverse).with(new_folder, type=RbVmomi::VIM::Folder, create=true).and_return(nil)

        expect{subject.create_folder(connection, new_folder, datacenter)}.to raise_error("Cannot create folder #{new_folder}")
      end
    end
  end

  describe '#migration_enabled?' do
    let(:config) {
      { :config => { 'migration_limit' => 5 } }
    }
    it 'returns true if migration is enabled' do
      result = subject.migration_enabled?(config)
      expect(result).to be true
    end

    context 'with migration disabled' do
      let(:config) {
        { :config => { } }
      }
      it 'should return false' do
        result = subject.migration_enabled?(config)
        expect(result).to be false
      end
    end

    context 'with non-integer value for migration limit' do
      let(:config) {
        { :config => { 'migration_limit' => 1.0 } }
      }
      it 'should return false' do
        result = subject.migration_enabled?(config)
        expect(result).to be false
      end
    end
  end

  describe '#find_least_used_hosts' do
    let(:cluster_name) { 'cluster' }
    let(:missing_cluster_name) { 'missing_cluster' }
    let(:datacenter_object) { mock_RbVmomi_VIM_Datacenter() }
    let(:percentage) { 100 }

    before(:each) do
      # This mocking is a little fragile but hard to do without a real vCenter instance
      allow(subject).to receive(:connect_to_vsphere).and_return(connection)
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
#,datacenter_name
      it 'should raise an error' do
        expect{subject.find_least_used_hosts(missing_cluster_name,datacenter_name,percentage)}.to raise_error(RuntimeError,/Cluster #{missing_cluster_name} cannot be found/)
      end
    end

    context 'standalone host within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({
        :name => cluster_name,
        :hosts => [{
          :name => cluster_name,
      }]})}
      let(:expected_host) { cluster_object.host[0][:name] }

      it 'should return the standalone host' do
        result = subject.find_least_used_hosts(cluster_name,datacenter_name,percentage)

        expect(result['hosts'][0]).to be(expected_host)
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
        expect{subject.find_least_used_hosts(missing_cluster_name,datacenter_name,percentage)}.to raise_error(RuntimeError,/Cluster #{missing_cluster_name} cannot be found/)
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
      let(:expected_host) { cluster_object.host[1].name }

      it 'should return the standalone host' do
        result = subject.find_least_used_hosts(cluster_name,datacenter_name,percentage)

        expect(result['hosts'][0]).to be(expected_host)
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
        expect{subject.find_least_used_hosts(missing_cluster_name,datacenter_name,percentage)}.to raise_error(RuntimeError,/Cluster #{missing_cluster_name} cannot be found/)
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
      let(:expected_host) { cluster_object.host[1].name }

      it 'should return the standalone host' do
        result = subject.find_least_used_hosts(cluster_name,datacenter_name,percentage)

        expect(result['hosts'][0]).to be(expected_host)
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
        result = subject.find_least_used_hosts(missing_cluster_name,datacenter_name,percentage)
        expect(result).to_not be_nil
      end
    end
  end

  describe '#find_cluster' do
    let(:cluster) {'cluster'}
    let(:missing_cluster) {'missing_cluster'}

    context 'no clusters in the datacenter' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name }
          ]
        }
      }}

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster,connection,datacenter_name)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
              :hostfolder_tree => {
                'cluster1' =>  {:object_type => 'compute_resource'},
                'cluster2' => {:object_type => 'compute_resource'},
                cluster => {:object_type => 'compute_resource'},
                'cluster3' => {:object_type => 'compute_resource'},
              }
            }
          ]
        }
      }}

      it 'should return the cluster when found' do
        result = subject.find_cluster(cluster,connection,datacenter_name)

        expect(result).to_not be_nil
        expect(result.name).to eq(cluster)
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster,connection,datacenter_name)).to be_nil
      end
    end

    context 'with a single layer folder hierarchy with multiple datacenters' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'AnotherDC',
              :hostfolder_tree => {
                'cluster1' =>  {:object_type => 'compute_resource'},
                'cluster2' => {:object_type => 'compute_resource'},
              }
            },
            { :name => datacenter_name,
              :hostfolder_tree => {
                cluster => {:object_type => 'compute_resource'},
                'cluster3' => {:object_type => 'compute_resource'},
              }
            }
          ]
        }
      }}

      it 'should return the cluster when found' do
        result = subject.find_cluster(cluster,connection,datacenter_name)

        expect(result).to_not be_nil
        expect(result.name).to eq(cluster)
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster,connection,'AnotherDC')).to be_nil
      end
    end

    context 'with a multi layer folder hierarchy' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name,
              :hostfolder_tree => {
                'cluster1' =>  {:object_type => 'compute_resource'},
                'folder2' => {
                  :children => {
                    cluster => {:object_type => 'compute_resource'},
                  }
                },
                'cluster3' => {:object_type => 'compute_resource'},
              }
            }
          ]
        }
      }}

      it 'should return the cluster when found' do
        pending('https://github.com/puppetlabs/vmpooler/issues/205')
        result = subject.find_cluster(cluster,connection,datacenter_name)

        expect(result).to_not be_nil
        expect(result.name).to eq(cluster)
      end

      it 'should return nil if the cluster is not found' do
        expect(subject.find_cluster(missing_cluster,connection,datacenter_name)).to be_nil
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

  describe '#find_least_used_vpshere_compatible_host' do
    let(:vm) { mock_RbVmomi_VIM_VirtualMachine() }

    context 'standalone host within limits' do
      let(:cluster_object) { mock_RbVmomi_VIM_ComputeResource({:hosts => [{}]}) }
      let(:standalone_host) { cluster_object.host[0] }

      before(:each) do
        # This mocking is a little fragile but hard to do without a real vCenter instance
        vm.summary.runtime.host = standalone_host
      end

      it 'should return the standalone host' do
        result = subject.find_least_used_vpshere_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(standalone_host)
        expect(result[1]).to eq(standalone_host.name)
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
        expect{subject.find_least_used_vpshere_compatible_host(vm)}.to raise_error(/There is no host candidate in vcenter that meets all the required conditions/)
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
        result = subject.find_least_used_vpshere_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(expected_host)
        expect(result[1]).to eq(expected_host.name)
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
        expect{subject.find_least_used_vpshere_compatible_host(vm)}.to raise_error(/There is no host candidate in vcenter that meets all the required conditions/)
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
        result = subject.find_least_used_vpshere_compatible_host(vm)

        expect(result).to_not be_nil
        expect(result[0]).to be(expected_host)
        expect(result[1]).to eq(expected_host.name)
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
        result = subject.find_least_used_vpshere_compatible_host(vm)

        expect(result).to_not be_nil
      end
    end
  end

  describe '#find_pool' do
    let(:poolname) { 'pool'}
    let(:missing_poolname) { 'missing_pool'}

    context 'with empty folder hierarchy' do
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => datacenter_name }
          ] 
        }
      }}

      it 'should ensure the connection' do
        pending('https://github.com/puppetlabs/vmpooler/issues/209')
        expect(subject).to receive(:ensure_connected)

        subject.find_pool(poolname,connection,datacenter_name)
      end

      it 'should return nil if the pool is not found' do
        pending('https://github.com/puppetlabs/vmpooler/issues/209')
        expect(subject.find_pool(missing_poolname,connection,datacenter_name)).to be_nil
      end
    end

    context 'with multiple datacenters' do
      let(:poolpath) { 'pool' }
      let(:connection_options) {{
        :serviceContent => {
          :datacenters => [
            { :name => 'AnotherDC',
              :hostfolder_tree => {
                'folder1' => nil,
                'folder2' => nil,
              },
            },
            { :name => datacenter_name,
              :hostfolder_tree => {
                'folder3' => nil,
                'pool' => {:object_type => 'resource_pool'},
                'folder4' => nil,
              },
            }
          ]
        }
      }}

      it 'should return the pool when found' do
        result = subject.find_pool(poolpath,connection, datacenter_name)

        expect(result).to_not be_nil
        expect(result.name).to eq('pool')
        expect(result.is_a?(RbVmomi::VIM::ResourcePool)).to be true
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
        let(:connection_options) {{
          :serviceContent => {
            :datacenters => [
              { :name => datacenter_name,
                :hostfolder_tree => testcase[:hostfolder_tree],
              }
            ]
          }
        }}

        it 'should return the pool when found' do
          result = subject.find_pool(testcase[:poolpath],connection,datacenter_name)

          expect(result).to_not be_nil
          expect(result.name).to eq(testcase[:poolname])
          expect(result.is_a?(RbVmomi::VIM::ResourcePool)).to be true
        end

        it 'should return nil if the poolname is not found' do
          pending('https://github.com/puppetlabs/vmpooler/issues/209')
          expect(subject.find_pool(missing_poolname,connection,datacenter_name)).to be_nil
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
        let(:connection_options) {{
          :serviceContent => {
            :datacenters => [
              { :name => datacenter_name,
                :hostfolder_tree => testcase[:hostfolder_tree],
              }
            ]
          }
        }}

        it 'should ensure the connection' do
          pending('https://github.com/puppetlabs/vmpooler/issues/210')
          expect(subject).to receive(:ensure_connected)

          subject.find_pool(testcase[:poolpath],connection,datacenter_name)
        end

        it 'should return the pool when found' do
          pending('https://github.com/puppetlabs/vmpooler/issues/210')
          result = subject.find_pool(testcase[:poolpath],connection,datacenter_name)

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
    let(:snapshot_object) { mock_RbVmomi_VIM_VirtualMachineSnapshot() }

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
      allow(subject).to receive(:find_vm_light).and_return('vmlight')
      allow(subject).to receive(:find_vm_heavy).and_return( { vmname => 'vmheavy' })
    end

    it 'should call find_vm_light' do
      expect(subject).to receive(:find_vm_light).and_return('vmlight')

      expect(subject.find_vm(vmname,connection)).to eq('vmlight')
    end

    it 'should not call find_vm_heavy if find_vm_light finds the VM' do
      expect(subject).to receive(:find_vm_light).and_return('vmlight')
      expect(subject).to receive(:find_vm_heavy).exactly(0).times

      expect(subject.find_vm(vmname,connection)).to eq('vmlight')
    end

    it 'should call find_vm_heavy when find_vm_light returns nil' do
      expect(subject).to receive(:find_vm_light).and_return(nil)
      expect(subject).to receive(:find_vm_heavy).and_return( { vmname => 'vmheavy' })

      expect(subject.find_vm(vmname,connection)).to eq('vmheavy')
    end
  end

  describe '#find_vm_light' do
    let(:missing_vm) { 'missing_vm' }

    before(:each) do
      allow(connection.searchIndex).to receive(:FindByDnsName).and_return(nil)
    end

    it 'should call FindByDnsName with the correct parameters' do
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: vmname,
      })

      subject.find_vm_light(vmname,connection)
    end

    it 'should return the VM object when found' do
      vm_object = mock_RbVmomi_VIM_VirtualMachine()
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: vmname,
      }).and_return(vm_object)

      expect(subject.find_vm_light(vmname,connection)).to be(vm_object)
    end

    it 'should return nil if the VM is not found' do
      expect(connection.searchIndex).to receive(:FindByDnsName).with({
        :vmSearch => true,
        dnsName: missing_vm,
      }).and_return(nil)

      expect(subject.find_vm_light(missing_vm,connection)).to be_nil
    end
  end

  describe '#find_vm_heavy' do
    let(:missing_vm) { 'missing_vm' }
    # Return an empty result by default
    let(:retrieve_result) {{}}

    before(:each) do
      allow(connection.propertyCollector).to receive(:RetrievePropertiesEx).and_return(mock_RbVmomi_VIM_RetrieveResult(retrieve_result))
    end

    context 'Search result is empty' do
      it 'should return empty hash' do
        expect(subject.find_vm_heavy(vmname,connection)).to eq({})
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
        expect(subject.find_vm_heavy(vmname,connection)).to eq({})
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
        result = subject.find_vm_heavy(vmname,connection)
        expect(result.keys.count).to eq(1)
      end

      it 'should return the matching VM Object' do
        result = subject.find_vm_heavy(vmname,connection)
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
        result = subject.find_vm_heavy(vmname,connection)
        expect(result.keys.count).to eq(1)
      end

      it 'should return the last matching VM Object' do
        result = subject.find_vm_heavy(vmname,connection)
        expect(result[vmname]).to be(vm_object2)
      end
    end
  end

  describe '#find_vmdks' do
    let(:datastorename) { 'datastore' }
    let(:connection_options) {{
      :serviceContent => {
        :datacenters => [
          { :name => datacenter_name, :datastores => [datastorename] }
        ]
      }
    }}

    let(:collectMultiple_response) { {} }

    before(:each) do
      allow(connection.serviceContent.propertyCollector).to receive(:collectMultiple).and_return(collectMultiple_response)
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
        expect(subject.find_vmdks('missing_vm_name',datastorename,connection,datacenter_name)).to eq([])
      end

      it 'should return matching VMDKs for the VM' do
        result = subject.find_vmdks(vmname,datastorename,connection,datacenter_name)
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
    it 'should return a recursive view of type VirtualMachine' do
      result = subject.get_base_vm_container_from(connection)

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

    it 'should call RelocateVM_Task' do
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


end
