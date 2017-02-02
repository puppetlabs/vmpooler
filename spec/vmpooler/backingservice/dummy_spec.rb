require 'spec_helper'

describe 'Vmpooler::PoolManager::BackingService::Dummy' do
  let(:logger) { double('logger') }

  let (:pool_hash) {
    pool = {}
    pool['name'] = 'pool1'

    pool
  }

  let (:default_config) {
    # Construct an initial state for testing
    dummylist = {}
    dummylist['pool'] = {}
    # pool1 is a pool of "normal" VMs
    dummylist['pool']['pool1'] = []
      # A normal running VM
      vm = {}
      vm['name'] = 'vm1'
      vm['hostname'] = 'vm1'
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = 'pool1'
      vm['poolname'] = 'pool1'
      vm['ready'] = true
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['dummy_state'] = 'RUNNING'
      dummylist['pool']['pool1'] << vm

    # pool2 is a pool of "abnormal" VMs e.g. PoweredOff etc.
    dummylist['pool']['pool2'] = []
      # A freshly provisioned VM that is not ready
      vm = {}
      vm['name'] = 'vm2'
      vm['hostname'] = 'vm2'
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = 'pool2'
      vm['poolname'] = 'pool2'
      vm['ready'] = false
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['dummy_state'] = 'UNKNOWN'
      dummylist['pool']['pool2'] << vm
      # A freshly provisioned VM that is running but not ready
      vm = {}
      vm['name'] = 'vm3'
      vm['hostname'] = 'vm3'
      vm['domain']  = 'dummy.local'
      vm['vm_template'] = 'template1'
      vm['template'] = 'pool2'
      vm['poolname'] = 'pool2'
      vm['ready'] = false
      vm['boottime'] = Time.now
      vm['powerstate'] = 'PoweredOn'
      vm['vm_host'] = 'HOST1'
      vm['dummy_state'] = 'RUNNING'
      dummylist['pool']['pool2'] << vm

    config = {}
    config['initial_state'] = dummylist

    config
  }

  let (:config) { default_config }

  subject { Vmpooler::PoolManager::BackingService::Dummy.new(config) }

  before do
    allow(logger).to receive(:log)
    $logger = logger
  end

  describe '#name' do
    it 'should be dummy' do
      expect(subject.name).to eq('dummy')
    end
  end

  describe '#vms_in_pool' do
    it 'should return [] when pool does not exist' do
      pool = pool_hash
      pool['name'] = 'pool_does_not_exist'

      vm_list = subject.vms_in_pool(pool)

      expect(vm_list).to eq([])
    end

    it 'should return an array of VMs when pool exists' do
      pool = pool_hash
      pool['name'] = 'pool1'

      vm_list = subject.vms_in_pool(pool)

      expect(vm_list.count).to eq(1)
    end
  end

  describe '#get_vm_host' do
    it 'should return the hostname when VM exists' do
      expect(subject.get_vm_host('vm1')).to eq('HOST1')
    end

    it 'should error when VM does not exist' do
      expect{subject.get_vm_host('doesnotexist')}.to raise_error(RuntimeError)
    end
  end

  describe '#find_least_used_compatible_host' do
    it 'should return the current host' do
      new_host = subject.find_least_used_compatible_host('vm1')
      expect(new_host).to eq('HOST1')
    end

    context 'using migratevm_couldmove_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['migratevm_couldmove_percent'] = 0
          config
        }

        it 'should return the current host' do
          new_host = subject.find_least_used_compatible_host('vm1')
          expect(new_host).to eq('HOST1')
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['migratevm_couldmove_percent'] = 100
          config
        }

        it 'should return a different host' do
          new_host = subject.find_least_used_compatible_host('vm1')
          expect(new_host).to_not eq('HOST1')
        end
      end

    end
  end

  describe '#migrate_vm_to_host' do
    it 'should move to the new host' do
      expect(subject.migrate_vm_to_host('vm1','NEWHOST')).to eq(true)
      expect(subject.get_vm_host('vm1')).to eq('NEWHOST')
    end

    context 'using migratevm_fail_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['migratevm_fail_percent'] = 0
          config
        }

        it 'should move to the new host' do
          expect(subject.migrate_vm_to_host('vm1','NEWHOST')).to eq(true)
          expect(subject.get_vm_host('vm1')).to eq('NEWHOST')
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['migratevm_fail_percent'] = 100
          config
        }

        it 'should raise an error' do
          expect{subject.migrate_vm_to_host('vm1','NEWHOST')}.to raise_error(/migratevm_fail_percent/)
        end
      end
    end
  end

  describe '#get_vm' do
    it 'should return the VM when VM exists' do
      vm = subject.get_vm('vm1')
      expect(vm['name']).to eq('vm1')
      expect(vm['powerstate']).to eq('PoweredOn')
      expect(vm['hostname']).to eq(vm['name'])
    end

    it 'should return nil when VM does not exist' do
      expect(subject.get_vm('doesnotexist')).to eq(nil)
    end

    context 'using getvm_poweroff_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['getvm_poweroff_percent'] = 0
          config
        }

        it 'will not power off a VM' do
          vm = subject.get_vm('vm1')
          expect(vm['name']).to eq('vm1')
          expect(vm['powerstate']).to eq('PoweredOn')
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['getvm_poweroff_percent'] = 100
          config
        }

        it 'will power off a VM' do
          vm = subject.get_vm('vm1')
          expect(vm['name']).to eq('vm1')
          expect(vm['powerstate']).to eq('PoweredOff')
        end
      end
    end

    context 'using getvm_rename_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['getvm_rename_percent'] = 0
          config
        }

        it 'will not rename a VM' do
          vm = subject.get_vm('vm1')
          expect(vm['name']).to eq('vm1')
          expect(vm['hostname']).to eq(vm['name'])
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['getvm_rename_percent'] = 100
          config
        }

        it 'will rename a VM' do
          vm = subject.get_vm('vm1')
          expect(vm['name']).to eq('vm1')
          expect(vm['hostname']).to_not eq(vm['name'])
        end
      end
    end
  end

  describe '#create_vm' do
    it 'should return a new VM' do
      expect(subject.create_vm(pool_hash,'newvm')['name']).to eq('newvm')
    end

    it 'should increase the number of VMs in the pool' do
      pool = pool_hash
      old_pool_count = subject.vms_in_pool(pool).count
      new_vm = subject.create_vm(pool_hash,'newvm')
      expect(subject.vms_in_pool(pool).count).to eq(old_pool_count + 1)
    end

    context 'using createvm_fail_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['createvm_fail_percent'] = 0
          config
        }

        it 'should return a new VM' do
          expect(subject.create_vm(pool_hash,'newvm')['name']).to eq('newvm')
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['createvm_fail_percent'] = 100
          config
        }

        it 'should raise an error' do
          expect{subject.create_vm(pool_hash,'newvm')}.to raise_error(/createvm_fail_percent/)
        end

        it 'new VM should not exist' do
          begin
            subject.create_vm(pool_hash,'newvm')
          rescue
          end
          expect(subject.get_vm('newvm')).to eq(nil)
        end
      end
    end
  end

  describe '#destroy_vm' do
    it 'should return true when destroyed' do
      expect(subject.destroy_vm('vm1','pool1')).to eq(true)
    end

    it 'should log if the VM is powered off' do
      expect(logger).to receive(:log).with('d', "[ ] [pool1] 'vm1' is being shut down")
      expect(subject.destroy_vm('vm1','pool1')).to eq(true)
    end

    it 'should return false if VM does not exist' do
      expect(subject.destroy_vm('doesnotexist','pool1')).to eq(false)
    end

    it 'should return false if VM is not in the correct pool' do
      expect(subject.destroy_vm('vm1','differentpool')).to eq(false)
    end

    context 'using destroyvm_fail_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['destroyvm_fail_percent'] = 0
          config
        }

        it 'should return true when destroyed' do
          expect(subject.destroy_vm('vm1','pool1')).to eq(true)
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['destroyvm_fail_percent'] = 100
          config
        }

        it 'should raise an error' do
          expect{subject.destroy_vm('vm1','pool1')}.to raise_error(/migratevm_fail_percent/)
        end
      end
    end
  end

  describe '#is_vm_ready?' do
    it 'should return true if ready' do
      expect(subject.is_vm_ready?('vm1','pool1',0)).to eq(true)
    end

    it 'should return false if VM does not exist' do
      expect(subject.is_vm_ready?('doesnotexist','pool1',0)).to eq(false)
    end

    it 'should return false if VM is not in the correct pool' do
      expect(subject.is_vm_ready?('vm1','differentpool',0)).to eq(false)
    end

    it 'should raise an error if timeout expires' do
      expect{subject.is_vm_ready?('vm2','pool2',1)}.to raise_error(Timeout::Error)
    end

    it 'should return true if VM becomes ready' do
      expect(subject.is_vm_ready?('vm3','pool2',1)).to eq(true)
    end

    context 'using vmready_fail_percent' do
      describe 'of zero' do
        let (:config) {
          config = default_config
          config['vmready_fail_percent'] = 0
          config
        }

        it 'should return true if VM becomes ready' do
          expect(subject.is_vm_ready?('vm3','pool2',1)).to eq(true)
        end
      end

      describe 'of 100' do
        let (:config) {
          config = default_config
          config['vmready_fail_percent'] = 100
          config
        }

        it 'should raise an error' do
          expect{subject.is_vm_ready?('vm3','pool2',1)}.to raise_error(/vmready_fail_percent/)
        end
      end
    end
  end

  describe '#vm_exists?' do
    it 'should return true when VM exists' do
      expect(subject.vm_exists?('vm1')).to eq(true)
    end

    it 'should return true when VM does not exist' do
      expect(subject.vm_exists?('doesnotexist')).to eq(false)
    end
  end
end
