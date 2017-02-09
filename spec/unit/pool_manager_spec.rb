require 'spec_helper'
require 'time'
require 'mock_redis'

describe 'Pool Manager' do
  let(:logger) { MockLogger.new }
  let(:redis) { MockRedis.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) { {} }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) { double('host') }

  subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

  describe '#check_pending_vm' do
    let(:vsphere) { double('vsphere') }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_pending_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_pending_vm).with(vm,pool,timeout,vsphere)

      subject.check_pending_vm(vm, pool, timeout, vsphere)
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

  describe '#_check_pending_vm' do
    let(:vsphere) { double('vsphere') }

    before do
      expect(subject).not_to be_nil
    end

    context 'host does not exist or not in pool' do
      it 'calls fail_pending_vm' do
        expect(vsphere).to receive(:find_vm).and_return(nil)
        expect(subject).to receive(:fail_pending_vm).with(vm, pool, timeout, false) 

        subject._check_pending_vm(vm, pool, timeout, vsphere)
      end
    end

    context 'host is in pool' do
      it 'calls move_pending_vm_to_ready if host is ready' do
        expect(vsphere).to receive(:find_vm).and_return(host)
        expect(subject).to receive(:open_socket).and_return(nil)
        expect(subject).to receive(:move_pending_vm_to_ready).with(vm, pool, host)

        subject._check_pending_vm(vm, pool, timeout, vsphere)
      end

      it 'calls fail_pending_vm if an error is raised' do
        expect(vsphere).to receive(:find_vm).and_return(host)
        expect(subject).to receive(:open_socket).and_raise(SocketError,'getaddrinfo: No such host is known')
        expect(subject).to receive(:fail_pending_vm).with(vm, pool, timeout)

        subject._check_pending_vm(vm, pool, timeout, vsphere)
      end
    end
  end

  describe '#remove_nonexistent_vm' do
    before do
      expect(subject).not_to be_nil
    end

    it 'removes VM from pending in redis' do
      create_pending_vm(pool,vm)

      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
      subject.remove_nonexistent_vm(vm, pool)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(false)
    end

    it 'logs msg' do
      expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")

      subject.remove_nonexistent_vm(vm, pool)
    end
  end

 describe '#fail_pending_vm' do
    before do
      expect(subject).not_to be_nil
    end

    before(:each) do
      create_pending_vm(pool,vm)
    end

    it 'takes no action if VM is not cloning' do
      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(nil)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
    end

    it 'takes no action if VM is within timeout' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Time.now.to_s)
      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(nil)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
    end

    it 'moves VM to completed queue if VM has exceeded timeout and exists' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(nil)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(false)
      expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
    end

    it 'logs message if VM has exceeded timeout and exists' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(nil)
    end

    it 'calls remove_nonexistent_vm if VM has exceeded timeout and does not exist' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(subject).to receive(:remove_nonexistent_vm).with(vm, pool)
      expect(subject.fail_pending_vm(vm, pool, timeout,false)).to eq(nil)
    end

    it 'swallows error if an error is raised' do
      redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(nil)
    end

    it 'logs message if an error is raised' do
      redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
      expect(logger).to receive(:log).with('d', String)

      subject.fail_pending_vm(vm, pool, timeout,true)
    end
  end
  
  describe '#move_pending_vm_to_ready' do
    before do
      expect(subject).not_to be_nil
      allow(Socket).to receive(:getaddrinfo)
    end

    before(:each) do
      create_pending_vm(pool,vm)
    end

    context 'when hostname does not match VM name' do
      it 'should not take any action' do
        expect(logger).to receive(:log).exactly(0).times
        expect(Socket).to receive(:getaddrinfo).exactly(0).times

        allow(host).to receive(:summary).and_return( double('summary') )
        allow(host).to receive_message_chain(:summary, :guest).and_return( double('guest') )
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return ('different_name')

        subject.move_pending_vm_to_ready(vm, pool, host)
      end
    end

    context 'when hostname matches VM name' do
      before do
        allow(host).to receive(:summary).and_return( double('summary') )
        allow(host).to receive_message_chain(:summary, :guest).and_return( double('guest') )
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return (vm)
      end

      it 'should move the VM from pending to ready pool' do
        expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
        expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(false)
        subject.move_pending_vm_to_ready(vm, pool, host)
        expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(false)
        expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(true)
      end

      it 'should log a message' do
        expect(logger).to receive(:log).with('s', "[>] [#{pool}] '#{vm}' moved to 'ready' queue")

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'should set the boot time in redis' do
        redis.hset("vmpooler__vm__#{vm}", 'clone',Time.now.to_s)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to be_nil
        subject.move_pending_vm_to_ready(vm, pool, host)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to_not be_nil
        # TODO Should we inspect the value to see if it's valid?
      end

      it 'should not determine boot timespan if clone start time not set' do
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to be_nil
        subject.move_pending_vm_to_ready(vm, pool, host)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to eq("") # Possible implementation bug here. Should still be nil here
      end

      it 'should raise error if clone start time is not parsable' do
        redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
        expect{subject.move_pending_vm_to_ready(vm, pool, host)}.to raise_error(/iamnotparsable_asdate/)
      end
    end
  end

  describe '#_check_running_vm' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    it 'does nothing with nil host' do
      allow(vsphere).to receive(:find_vm).and_return(nil)
      expect(redis).not_to receive(:smove)
      subject._check_running_vm(vm, pool, timeout, vsphere)
    end

    context 'valid host' do
      let(:vm_host) { double('vmhost') }

      it 'does not move vm when not poweredOn' do
        allow(vsphere).to receive(:find_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOff'

        expect(redis).to receive(:hget)
        expect(redis).not_to receive(:smove)
        expect(logger).not_to receive(:log).with('d', "[!] [#{pool}] '#{vm}' appears to be powered off or dead")

        subject._check_running_vm(vm, pool, timeout, vsphere)
      end

      it 'moves vm when poweredOn, but past TTL' do
        allow(vsphere).to receive(:find_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOn'

        expect(redis).to receive(:hget).with('vmpooler__active__pool1', 'vm1').and_return((Time.now - timeout*60*60).to_s)
        expect(redis).to receive(:smove)
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{timeout} hours")

        subject._check_running_vm(vm, pool, timeout, vsphere)
      end
    end
  end

  describe '#move_running_to_completed' do
    before do
      expect(subject).not_to be_nil
    end

    it 'uses the pool in smove' do
      allow(redis).to receive(:smove).with(String, String, String)
      allow(logger).to receive(:log)
      expect(redis).to receive(:smove).with('vmpooler__running__p1', 'vmpooler__completed__p1', 'vm1')
      subject.move_vm_queue('p1', 'vm1', 'running', 'completed', 'msg')
    end

    it 'logs msg' do
      allow(redis).to receive(:smove)
      allow(logger).to receive(:log)
      expect(logger).to receive(:log).with('d', "[!] [p1] 'vm1' a msg here")
      subject.move_vm_queue('p1', 'vm1', 'running', 'completed', 'a msg here')
    end
  end

  describe '#_check_pool' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }
    let(:config) { {
      config: { task_limit: 10 },
      pools: [ {'name' => 'pool1', 'size' => 5} ]
    } }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
      allow(logger).to receive(:log)
      allow(pool_helper).to receive(:find_folder)
      allow(redis).to receive(:smembers).with('vmpooler__pending__pool1').and_return([])
      allow(redis).to receive(:smembers).with('vmpooler__ready__pool1').and_return([])
      allow(redis).to receive(:smembers).with('vmpooler__running__pool1').and_return([])
      allow(redis).to receive(:smembers).with('vmpooler__completed__pool1').and_return([])
      allow(redis).to receive(:smembers).with('vmpooler__discovered__pool1').and_return([])
      allow(redis).to receive(:smembers).with('vmpooler__migrating__pool1').and_return([])
      allow(redis).to receive(:set)
      allow(redis).to receive(:get).with('vmpooler__tasks__clone').and_return(0)
      allow(redis).to receive(:get).with('vmpooler__empty__pool1').and_return(nil)
    end

    context 'logging' do
      it 'logs empty pool' do
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(0)

        expect(logger).to receive(:log).with('s', "[!] [pool1] is empty")
        subject._check_pool(config[:pools][0], vsphere)
      end
    end
  end

  describe '#_stats_running_ready' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }
    let(:metrics) { Vmpooler::DummyStatsd.new }
    let(:config) { {
      config: { task_limit: 10 },
      pools: [ {'name' => 'pool1', 'size' => 5} ],
      graphite: { 'prefix' => 'vmpooler' }
    } }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
      allow(logger).to receive(:log)
      allow(pool_helper).to receive(:find_folder)
      allow(redis).to receive(:smembers).and_return([])
      allow(redis).to receive(:set)
      allow(redis).to receive(:get).with('vmpooler__tasks__clone').and_return(0)
      allow(redis).to receive(:get).with('vmpooler__empty__pool1').and_return(nil)
    end

    context 'metrics' do
      subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

      it 'increments metrics' do
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(1)
        allow(redis).to receive(:scard).with('vmpooler__cloning__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(5)

        expect(metrics).to receive(:gauge).with('ready.pool1', 1)
        expect(metrics).to receive(:gauge).with('running.pool1', 5)
        subject._check_pool(config[:pools][0], vsphere)
      end

      it 'increments metrics when ready with 0 when pool empty' do
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__cloning__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(5)

        expect(metrics).to receive(:gauge).with('ready.pool1', 0)
        expect(metrics).to receive(:gauge).with('running.pool1', 5)
        subject._check_pool(config[:pools][0], vsphere)
      end
    end
  end

  describe '#_create_vm_snapshot' do
    let(:snapshot_manager) { 'snapshot_manager' }
    let(:pool_helper) { double('snapshot_manager') }
    let(:vsphere) { {snapshot_manager => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    context '(valid host)' do
      let(:vm_host) { double('vmhost') }

      it 'creates a snapshot' do
        expect(vsphere).to receive(:find_vm).and_return vm_host
        expect(logger).to receive(:log)
        expect(vm_host).to receive_message_chain(:CreateSnapshot_Task, :wait_for_completion)
        expect(redis).to receive(:hset).with('vmpooler__vm__testvm', 'snapshot:testsnapshot', Time.now.to_s)
        expect(logger).to receive(:log)

        subject._create_vm_snapshot('testvm', 'testsnapshot', vsphere)
      end
    end
  end

  describe '#_revert_vm_snapshot' do
    let(:snapshot_manager) { 'snapshot_manager' }
    let(:pool_helper) { double('snapshot_manager') }
    let(:vsphere) { {snapshot_manager => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    context '(valid host)' do
      let(:vm_host) { double('vmhost') }
      let(:vm_snapshot) { double('vmsnapshot') }

      it 'reverts a snapshot' do
        expect(vsphere).to receive(:find_vm).and_return vm_host
        expect(vsphere).to receive(:find_snapshot).and_return vm_snapshot
        expect(logger).to receive(:log)
        expect(vm_snapshot).to receive_message_chain(:RevertToSnapshot_Task, :wait_for_completion)
        expect(logger).to receive(:log)

        subject._revert_vm_snapshot('testvm', 'testsnapshot', vsphere)
      end
    end
  end

  describe '#_check_snapshot_queue' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    it 'checks appropriate redis queues' do
      expect(redis).to receive(:spop).with('vmpooler__tasks__snapshot')
      expect(redis).to receive(:spop).with('vmpooler__tasks__snapshot-revert')

      subject._check_snapshot_queue(vsphere)
    end
  end
end
