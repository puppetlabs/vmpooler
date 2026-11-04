# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/providers/dummy'

describe 'Vmpooler::PoolManager::Provider::Dummy' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:pool_name) { 'pool1' }
  let(:other_pool_name) { 'pool2' }
  let(:vm_name) { 'vm1' }

  let(:running_vm_name) { 'vm2' }
  let(:notready_vm_name) { 'vm3' }

  let(:provider_options) do
    # Construct an initial state for testing
    dummylist = {}
    dummylist['pool'] = {}
    # pool1 is a pool of "normal" VMs
    dummylist['pool'][pool_name] = []
    # A normal running VM
    vm = {}
    vm['name'] = vm_name
    vm['hostname'] = vm_name
    vm['domain'] = 'dummy.local'
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
    vm['domain'] = 'dummy.local'
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
    vm['domain'] = 'dummy.local'
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
  end

  let(:config) do
    YAML.safe_load(<<~YAML_CONFIG, permitted_classes: [Symbol])
      ---
      :config:
      :providers:
        :dummy:
          key1: 'value1'
          # Drop the connection pool timeout way down for spec tests so they fail fast
          connection_pool_timeout: 1
      :pools:
        - name: '#{pool_name}'
          size: 5
        - name: 'pool2'
          size: 5
    YAML_CONFIG
  end

  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { MockRedis.new } }

  subject { Vmpooler::PoolManager::Provider::Dummy.new(config, logger, metrics, redis_connection_pool, 'dummy', provider_options) }

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
      expect { subject.get_vm_host(pool_name, 'doesnotexist') }.to raise_error(RuntimeError)
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
      expect(subject.migrate_vm_to_host(pool_name, 'vm1', 'NEWHOST')).to eq(true)
      expect(subject.get_vm_host(pool_name, 'vm1')).to eq('NEWHOST')
    end

    context 'using migratevm_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['migratevm_fail_percent'] = 0
        end

        it 'should move to the new host' do
          expect(subject.migrate_vm_to_host(pool_name, 'vm1', 'NEWHOST')).to eq(true)
          expect(subject.get_vm_host(pool_name, 'vm1')).to eq('NEWHOST')
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['migratevm_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect { subject.migrate_vm_to_host(pool_name, 'vm1', 'NEWHOST') }.to raise_error(/migratevm_fail_percent/)
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

      subject.create_vm(pool_name, new_vm_name)

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
          expect { subject.create_vm(pool_name, new_vm_name) }.to raise_error(/createvm_fail_percent/)
        end

        it 'new VM should not exist' do
          expect { subject.create_vm(pool_name, new_vm_name) }.to raise_error(StandardError)
          expect(subject.get_vm(pool_name, new_vm_name)).to eq(nil)
        end
      end
    end
  end

  describe '#create_disk' do
    let(:disk_size) { 10 }

    it 'should return true when the disk is created' do
      expect(subject.create_disk(pool_name, vm_name, disk_size)).to be true
    end

    it 'should raise an error when VM does not exist' do
      expect { subject.create_disk(pool_name, 'doesnotexist', disk_size) }.to raise_error(/VM doesnotexist does not exist/)
    end

    context 'using createdisk_fail_percent' do
      describe 'of zero' do
        before(:each) do
          config[:providers][:dummy]['createdisk_fail_percent'] = 0
        end

        it 'should return true when the disk is created' do
          expect(subject.create_disk(pool_name, vm_name, disk_size)).to be true
        end
      end

      describe 'of 100' do
        before(:each) do
          config[:providers][:dummy]['createdisk_fail_percent'] = 100
        end

        it 'should raise an error' do
          expect { subject.create_disk(pool_name, vm_name, disk_size) }.to raise_error(/createdisk_fail_percent/)
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
      expect { subject.create_snapshot(pool_name, 'doesnotexist', snapshot_name) }.to raise_error(/VM doesnotexist does not exist/)
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
          expect { subject.create_snapshot(pool_name, vm_name, snapshot_name) }.to raise_error(/createsnapshot_fail_percent/)
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
      expect { subject.revert_snapshot(pool_name, 'doesnotexist', snapshot_name) }.to raise_error(/VM doesnotexist does not exist/)
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
          expect { subject.revert_snapshot(pool_name, vm_name, snapshot_name) }.to raise_error(/revertsnapshot_fail_percent/)
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
      expect(subject.destroy_vm('doesnotexist', vm_name)).to eq(false)
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
          expect { subject.destroy_vm(pool_name, vm_name) }.to raise_error(/migratevm_fail_percent/)
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
      expect { subject.vm_ready?(other_pool_name, running_vm_name) }.to raise_error(Timeout::Error)
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
          expect { subject.vm_ready?(other_pool_name, notready_vm_name) }.to raise_error(/vmready_fail_percent/)
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

  describe 'simulated delays' do
    let(:dummy_config) { config[:providers][:dummy] }

    before(:each) do
      # rand(n) gives n - 1, so each delay is 1 + (n - 1) = n seconds, and no failure is injected
      allow(subject).to receive(:rand) { |limit| limit.is_a?(Range) ? limit.last + 1 : limit - 1 }
      allow(subject).to receive(:sleep)
    end

    it 'waits when migrating a VM' do
      dummy_config['migratevm_max_time'] = 5

      expect(subject.migrate_vm_to_host(pool_name, vm_name, 'HOST2')).to eq(true)

      expect(subject).to have_received(:sleep).with(5)
      expect(subject.get_vm_host(pool_name, vm_name)).to eq('HOST2')
    end

    it 'waits while a VM is cloning, then leaves it running' do
      dummy_config['createvm_max_time'] = 7

      subject.create_vm(pool_name, 'slowvm')

      expect(subject).to have_received(:sleep).with(7)
      expect(subject.get_vm(pool_name, 'slowvm')).not_to be_nil
    end

    it 'waits when creating a disk' do
      dummy_config['createdisk_max_time'] = 3

      subject.create_disk(pool_name, vm_name, 10)

      expect(subject).to have_received(:sleep).with(3)
    end

    it 'waits when creating a snapshot' do
      dummy_config['createsnapshot_max_time'] = 4

      subject.create_snapshot(pool_name, vm_name, 'snap1')

      expect(subject).to have_received(:sleep).with(4)
    end

    it 'waits when reverting to a snapshot' do
      dummy_config['revertsnapshot_max_time'] = 6
      subject.create_snapshot(pool_name, vm_name, 'snap1')

      subject.revert_snapshot(pool_name, vm_name, 'snap1')

      expect(subject).to have_received(:sleep).with(6)
    end

    it 'waits for the shutdown and again for the destroy' do
      dummy_config['destroyvm_max_shutdown_time'] = 2
      dummy_config['destroyvm_max_time'] = 8

      expect(subject.destroy_vm(pool_name, vm_name)).to eq(true)

      expect(subject).to have_received(:sleep).with(2).ordered
      expect(subject).to have_received(:sleep).with(8).ordered
    end

    it 'does not wait when no delay is configured' do
      subject.create_vm(pool_name, 'quickvm')
      subject.destroy_vm(pool_name, vm_name)

      expect(subject).not_to have_received(:sleep)
    end
  end

  describe 'the backing file' do
    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @backing_file = File.join(dir, 'dummy.yaml')
        example.run
      end
    end

    it 'is written when a VM is created' do
      config[:providers][:dummy]['filename'] = @backing_file

      subject.create_vm(pool_name, 'savedvm')

      saved = YAML.load_file(@backing_file, permitted_classes: [Time, Symbol])
      expect(saved['pool'][pool_name].map { |vm| vm['name'] }).to include('savedvm')
    end

    it 'is not written when no file is configured' do
      subject.create_vm(pool_name, 'unsavedvm')

      expect(File.exist?(@backing_file)).to be false
    end
  end
  describe '#get_vm_ip_address' do
    let(:pool_name) { 'pool1' }
    let(:vm_name) { 'vm-ip-test' }

    it 'returns nil for a VM that does not exist' do
      expect(subject.get_vm_ip_address('doesnotexist', pool_name)).to be_nil
    end

    it 'returns the same address for the same VM, in 10.0.0.0/16' do
      subject.create_vm(pool_name, vm_name)

      ip = subject.get_vm_ip_address(vm_name, pool_name)

      expect(ip).to match(/\A10\.0\.\d{1,3}\.\d{1,3}\z/)
      expect(subject.get_vm_ip_address(vm_name, pool_name)).to eq(ip)
    end
  end
end
