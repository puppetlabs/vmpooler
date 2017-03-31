require 'spec_helper'

describe 'Vmpooler::PoolManager::Provider::Dummy' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:pool_name) { 'pool1' }
  let(:other_pool_name) { 'pool2' }
  let(:vm_name) { 'vm1' }

  let(:running_vm_name) { 'vm2' }
  let(:notready_vm_name) { 'vm3' }

  let (:provider_options) {
    # Construct an initial state for testing
    dummylist = {}
    dummylist['pool'] = {}
    # pool1 is a pool of "normal" VMs
    dummylist['pool'][pool_name] = []
      # A normal running VM
      vm = {}
      vm['name'] = vm_name
      vm['hostname'] = vm_name
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = pool_name
      vm['poolname'] = pool_name
      vm['ready'] = true
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['snapshots'] = []
      vm['disks'] = []
      vm['dummy_state'] = 'RUNNING'
      dummylist['pool'][pool_name] << vm

    # pool2 is a pool of "abnormal" VMs e.g. PoweredOff etc.
    dummylist['pool'][other_pool_name] = []
      # A freshly provisioned VM that is not ready
      vm = {}
      vm['name'] = running_vm_name
      vm['hostname'] = running_vm_name
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = other_pool_name
      vm['poolname'] = other_pool_name
      vm['ready'] = false
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['snapshots'] = []
      vm['disks'] = []
      vm['dummy_state'] = 'UNKNOWN'
      dummylist['pool'][other_pool_name] << vm
      # A freshly provisioned VM that is running but not ready
      vm = {}
      vm['name'] = notready_vm_name
      vm['hostname'] = notready_vm_name
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = other_pool_name
      vm['poolname'] = other_pool_name
      vm['ready'] = false
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['snapshots'] = []
      vm['disks'] = []
      vm['dummy_state'] = 'RUNNING'
      dummylist['pool'][other_pool_name] << vm

    {
      'initial_state' => dummylist
    }
  }

  let(:config) { YAML.load(<<-EOT
---
:config:
  max_tries: 3
  retry_factor: 10
:providers:
  :dummy:
    key1: 'value1'
:pools:
  - name: '#{pool_name}'
    size: 5
  - name: 'pool2'
    size: 5
EOT
    )
  }

  subject { Vmpooler::PoolManager::Provider::Dummy.new(config, logger, metrics, 'dummy', provider_options) }

  describe '#name' do
    it 'should be dummy' do
      expect(subject.name).to eq('dummy')
    end
  end

  describe '#vms_in_pool' do
    it 'should return [] when pool does not exist' do
      vm_list = subject.vms_in_pool('missing_pool')

      expect(vm_list).to eq([])
    end

    it 'should return an array of VMs when pool exists' do
      vm_list = subject.vms_in_pool(pool_name)

      expect(vm_list.count).to eq(1)
    end
  end

  describe '#get_vm_host' do
    it 'should return the hostname when VM exists' do
      expect(subject.get_vm_host(pool_name, vm_name)).to eq('HOST1')
    end

    it 'should error when VM does not exist' do
      expect{subject.get_vm_host(pool_name, 'doesnotexist')}.to raise_error(RuntimeError)
    end
  end

  describe '#find_least_used_compatible_host' do
    it 'should return the current host' do
      new_host = subject.find_least_used_compatible_host(pool_name, vm_name)
      expect(new_host).to eq('HOST1')
    end

    context 'using migratevm_couldmove_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['migratevm_couldmove_percent'] = 0
        end

        it 'should return the current host' do
          new_host = subject.find_least_used_compatible_host(pool_name, vm_name)
          expect(new_host).to eq('HOST1')
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['migratevm_couldmove_percent'] = 100
        end

        it 'should return a different host' do
          new_host = subject.find_least_used_compatible_host(pool_name, vm_name)
          expect(new_host).to_not eq('HOST1')
        end
      end

    end
  end

  describe '#migrate_vm_to_host' do
    it 'should move to the new host' do
      expect(subject.migrate_vm_to_host(pool_name, 'vm1','NEWHOST')).to eq(true)
      expect(subject.get_vm_host(pool_name, 'vm1')).to eq('NEWHOST')
    end

    context 'using migratevm_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['migratevm_fail_percent'] = 0
        end

        it 'should move to the new host' do
          expect(subject.migrate_vm_to_host(pool_name, 'vm1','NEWHOST')).to eq(true)
          expect(subject.get_vm_host(pool_name, 'vm1')).to eq('NEWHOST')
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['migratevm_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{subject.migrate_vm_to_host(pool_name, 'vm1','NEWHOST')}.to raise_error(/migratevm_fail_percent/)
        end
      end
    end
  end

  describe '#get_vm' do
    it 'should return the VM when VM exists' do
      vm = subject.get_vm(pool_name, vm_name)
      expect(vm['name']).to eq(vm_name)
      expect(vm['powerstate']).to eq('PoweredOn')
      expect(vm['hostname']).to eq(vm['name'])
    end

    it 'should return nil when VM does not exist' do
      expect(subject.get_vm(pool_name, 'doesnotexist')).to eq(nil)
    end

    context 'using getvm_poweroff_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['getvm_poweroff_percent'] = 0
        end

        it 'will not power off a VM' do
          vm = subject.get_vm(pool_name, vm_name)
          expect(vm['name']).to eq(vm_name)
          expect(vm['powerstate']).to eq('PoweredOn')
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['getvm_poweroff_percent'] = 100
        end

        it 'will power off a VM' do
          vm = subject.get_vm(pool_name, vm_name)
          expect(vm['name']).to eq(vm_name)
          expect(vm['powerstate']).to eq('PoweredOff')
        end
      end
    end

    context 'using getvm_rename_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['getvm_rename_percent'] = 0
        end

        it 'will not rename a VM' do
          vm = subject.get_vm(pool_name, vm_name)
          expect(vm['name']).to eq(vm_name)
          expect(vm['hostname']).to eq(vm['name'])
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['getvm_rename_percent'] = 100
        end

        it 'will rename a VM' do
          vm = subject.get_vm(pool_name, vm_name)
          expect(vm['name']).to eq(vm_name)
          expect(vm['hostname']).to_not eq(vm['name'])
        end
      end
    end
  end

  describe '#create_vm' do
    let(:new_vm_name) { 'newvm' }

    it 'should return a new VM' do
      expect(subject.create_vm(pool_name, new_vm_name)['name']).to eq(new_vm_name)
    end

    it 'should increase the number of VMs in the pool' do
      old_pool_count = subject.vms_in_pool(pool_name).count

      new_vm = subject.create_vm(pool_name, new_vm_name)

      expect(subject.vms_in_pool(pool_name).count).to eq(old_pool_count + 1)
    end

    context 'using createvm_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['createvm_fail_percent'] = 0
        end

        it 'should return a new VM' do
      expect(subject.create_vm(pool_name, new_vm_name)['name']).to eq(new_vm_name)
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['createvm_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{subject.create_vm(pool_name, new_vm_name)}.to raise_error(/createvm_fail_percent/)
        end

        it 'new VM should not exist' do
          begin
            subject.create_vm(pool_name, new_vm_name)
          rescue
          end
          expect(subject.get_vm(pool_name, new_vm_name)).to eq(nil)
        end
      end
    end
  end

  describe '#create_disk' do
    let(:disk_size) { 10 }

    it 'should return true when the disk is created' do
      expect(subject.create_disk(pool_name, vm_name,disk_size)).to be true
    end

    it 'should raise an error when VM does not exist' do
      expect{ subject.create_disk(pool_name, 'doesnotexist',disk_size) }.to raise_error(/VM doesnotexist does not exist/)
    end

    context 'using createdisk_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['createdisk_fail_percent'] = 0
        end

        it 'should return true when the disk is created' do
          expect(subject.create_disk(pool_name, vm_name,disk_size)).to be true
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['createdisk_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{subject.create_disk(pool_name, vm_name,disk_size)}.to raise_error(/createdisk_fail_percent/)
        end
      end
    end
  end

  describe '#create_snapshot' do
    let(:snapshot_name) { 'newsnapshot' }

    it 'should return true when the snapshot is created' do
      expect(subject.create_snapshot(pool_name, vm_name, snapshot_name)).to be true
    end

    it 'should raise an error when VM does not exist' do
      expect{ subject.create_snapshot(pool_name, 'doesnotexist', snapshot_name) }.to raise_error(/VM doesnotexist does not exist/)
    end

    context 'using createsnapshot_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['createsnapshot_fail_percent'] = 0
        end

        it 'should return true when the disk is created' do
          expect(subject.create_snapshot(pool_name, vm_name, snapshot_name)).to be true
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['createsnapshot_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{ subject.create_snapshot(pool_name, vm_name, snapshot_name) }.to raise_error(/createsnapshot_fail_percent/)
        end
      end
    end
  end

  describe '#revert_snapshot' do
    let(:snapshot_name) { 'newsnapshot' }

    before(:each) do
      # Create a snapshot
      subject.create_snapshot(pool_name, vm_name, snapshot_name)
    end

    it 'should return true when the snapshot is reverted' do
      expect(subject.revert_snapshot(pool_name, vm_name, snapshot_name)).to be true
    end

    it 'should raise an error when VM does not exist' do
      expect{ subject.revert_snapshot(pool_name, 'doesnotexist', snapshot_name) }.to raise_error(/VM doesnotexist does not exist/)
    end

    it 'should return false when the snapshot does not exist' do
      expect(subject.revert_snapshot(pool_name, vm_name, 'doesnotexist')).to be false
    end

    context 'using revertsnapshot_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['revertsnapshot_fail_percent'] = 0
        end

        it 'should return true when the snapshot is reverted' do
          expect(subject.revert_snapshot(pool_name, vm_name, snapshot_name)).to be true
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['revertsnapshot_fail_percent'] = 100
        end

        it 'should raise an error when VM does not exist' do
          expect{ subject.revert_snapshot(pool_name, vm_name, snapshot_name) }.to raise_error(/revertsnapshot_fail_percent/)
        end
      end
    end
  end

  describe '#destroy_vm' do
    it 'should return true when destroyed' do
      expect(subject.destroy_vm(pool_name, vm_name)).to eq(true)
    end

    it 'should log if the VM is powered off' do
      allow(logger).to receive(:log)
      expect(logger).to receive(:log).with('d', "[ ] [pool1] 'vm1' is being shut down")
      expect(subject.destroy_vm(pool_name, vm_name)).to eq(true)
    end

    it 'should return false if VM does not exist' do
      expect(subject.destroy_vm('doesnotexist',vm_name)).to eq(false)
    end

    it 'should return false if VM is not in the correct pool' do
      expect(subject.destroy_vm(other_pool_name, vm_name)).to eq(false)
    end

    context 'using destroyvm_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['destroyvm_fail_percent'] = 0
        end

        it 'should return true when destroyed' do
          expect(subject.destroy_vm(pool_name, vm_name)).to eq(true)
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['destroyvm_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{subject.destroy_vm(pool_name, vm_name)}.to raise_error(/migratevm_fail_percent/)
        end
      end
    end
  end

  describe '#vm_ready?' do
    before(:each) do
      # Speed up tests and ignore sleeping
      allow(subject).to receive(:sleep)
    end

    it 'should return true if ready' do
      expect(subject.vm_ready?(pool_name, vm_name)).to eq(true)
    end

    it 'should return false if VM does not exist' do
      expect(subject.vm_ready?(pool_name, 'doesnotexist')).to eq(false)
    end

    it 'should return false if VM is not in the correct pool' do
      expect(subject.vm_ready?(other_pool_name, vm_name)).to eq(false)
    end

    it 'should raise an error if timeout expires' do
      expect{subject.vm_ready?(other_pool_name, running_vm_name)}.to raise_error(Timeout::Error)
    end

    it 'should return true if VM becomes ready' do
      expect(subject.vm_ready?(other_pool_name, notready_vm_name)).to eq(true)
    end

    context 'using vmready_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['vmready_fail_percent'] = 0
        end

        it 'should return true if VM becomes ready' do
          expect(subject.vm_ready?(other_pool_name, notready_vm_name)).to eq(true)
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['vmready_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect{subject.vm_ready?(other_pool_name, notready_vm_name)}.to raise_error(/vmready_fail_percent/)
        end
      end
    end
  end

  describe '#vm_exists?' do
    it 'should return true when VM exists' do
      expect(subject.vm_exists?(pool_name, vm_name)).to eq(true)
    end

    it 'should return true when VM does not exist' do
      expect(subject.vm_exists?(pool_name, 'doesnotexist')).to eq(false)
    end
  end
end
