require 'spec_helper'
require 'time'

describe 'Pool Manager' do
  let(:logger) { double('logger') }
  let(:redis) { double('redis') }
  let(:config) { {} }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) { double('host') }

  subject { Vmpooler::PoolManager.new(config, logger, redis) }

  describe '#_check_pending_vm' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    context 'host not in pool' do

      it 'calls fail_pending_vm' do
        allow(pool_helper).to receive(:find_vm).and_return(nil)
        allow(redis).to receive(:hget)
        expect(redis).to receive(:hget).with(String, 'clone').once
        subject._check_pending_vm(vm, pool, timeout)
      end

    end

    context 'host is in pool' do
      let(:vm_finder) { double('vm_finder') }
      let(:tcpsocket) { double('TCPSocket') }

      it 'calls move_pending_vm_to_ready' do
        stub_const("TCPSocket", tcpsocket)

        allow(pool_helper).to receive(:find_vm).and_return(vm_finder)
        allow(vm_finder).to receive(:summary).and_return(nil)
        allow(tcpsocket).to receive(:new).and_return(true)

        expect(vm_finder).to receive(:summary).once
        expect(redis).not_to receive(:hget).with(String, 'clone')

        subject._check_pending_vm(vm, pool, timeout)
      end
    end
  end

  describe '#move_vm_to_ready' do
    before do
      expect(subject).not_to be_nil
    end

    context 'a host without correct summary' do

      it 'does nothing when summary is nil' do
        allow(host).to receive(:summary).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when guest is nil' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when hostName is nil' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when hostName does not match vm' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return 'adifferentvm'
        subject.move_pending_vm_to_ready(vm, pool, host)
      end
    end

    context 'a host with proper summary' do
      before do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return vm

        allow(redis).to receive(:hget)
        allow(redis).to receive(:smove)
        allow(redis).to receive(:hset)
        allow(logger).to receive(:log)
      end

      it 'moves vm to ready' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return Time.now.to_s

        expect(redis).to receive(:smove).with(String, String, vm)
        expect(redis).to receive(:hset).with(String, String, String)
        expect(logger).to receive(:log).with('s', String)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'sets finish to nil when clone_time is nil' do
        expect(redis).to receive(:smove).with(String, String, vm)
        expect(redis).to receive(:hset).with(String, String, nil)
        expect(logger).to receive(:log).with('s', String)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

    end
  end

  describe '#fail_pending_vm' do
    before do
      expect(subject).not_to be_nil
    end

    context 'does not have a clone stamp' do
      it 'has no side effects' do
        allow(redis).to receive(:hget)
        subject.fail_pending_vm(vm, pool, timeout)
      end
    end

    context 'has valid clone stamp' do
      it 'does nothing when less than timeout' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return Time.now.to_s
        subject.fail_pending_vm(vm, pool, timeout)
      end

      it 'moves vm to completed when over timeout' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return '2005-01-1'
        allow(redis).to receive(:smove).with(String, String, String)
        allow(logger).to receive(:log).with(String, String)

        expect(redis).to receive(:smove).with(String, String, vm)
        expect(logger).to receive(:log).with('d', String)

        subject.fail_pending_vm(vm, pool, timeout)
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
      allow(pool_helper).to receive(:find_vm).and_return(nil)
      expect(redis).not_to receive(:smove)
      subject._check_running_vm(vm, pool, timeout)
    end

    context 'valid host' do
      let(:vm_host) { double('vmhost') }

      it 'does not move vm when not poweredOn' do
        allow(pool_helper).to receive(:find_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOff'

        expect(redis).to receive(:hget)
        expect(redis).not_to receive(:smove)
        expect(logger).not_to receive(:log).with('d', "[!] [#{pool}] '#{vm}' appears to be powered off or dead")

        subject._check_running_vm(vm, pool, timeout)
      end

      it 'moves vm when poweredOn, but past TTL' do
        allow(pool_helper).to receive(:find_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOn'

        expect(redis).to receive(:hget).with('vmpooler__active__pool1', 'vm1').and_return((Time.now - timeout*60*60).to_s)
        expect(redis).to receive(:smove)
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{timeout} hours")

        subject._check_running_vm(vm, pool, timeout)
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
      allow(redis).to receive(:set)
      allow(redis).to receive(:get).with('vmpooler__tasks__clone').and_return(0)
      allow(redis).to receive(:get).with('vmpooler__empty__pool1').and_return(nil)
    end

    context 'logging' do

      it 'logs empty pool' do
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(0)

        expect(logger).to receive(:log).with('s', "[!] [pool1] is empty")
        subject._check_pool(config[:pools][0])
      end

    end
  end

  describe '#_stats_running_ready' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }
    let(:graphite) { double('graphite') }
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

    context 'graphite' do
      let(:graphite) { double('graphite') }
      subject { Vmpooler::PoolManager.new(config, logger, redis, graphite) }

      it 'increments graphite when enabled and statsd disabled' do
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(1)
        allow(redis).to receive(:scard).with('vmpooler__cloning__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(5)

        expect(graphite).to receive(:log).with('vmpooler.ready.pool1', 1)
        expect(graphite).to receive(:log).with('vmpooler.running.pool1', 5)
        subject._check_pool(config[:pools][0])
      end
    end

    context 'statsd' do
      let(:statsd) { double('statsd') }
      let(:config) { {
        config: { task_limit: 10 },
        pools: [ {'name' => 'pool1', 'size' => 5} ],
        statsd: { 'prefix' => 'vmpooler' }
      } }
      subject { Vmpooler::PoolManager.new(config, logger, redis, graphite, statsd) }

      it 'increments statsd when configured' do
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(1)
        allow(redis).to receive(:scard).with('vmpooler__cloning__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(5)

        expect(statsd).to receive(:increment).with('vmpooler.ready.pool1', 1)
        expect(statsd).to receive(:increment).with('vmpooler.running.pool1', 5)
        subject._check_pool(config[:pools][0])
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
        expect(pool_helper).to receive(:find_vm).and_return vm_host
        expect(logger).to receive(:log)
        expect(vm_host).to receive_message_chain(:CreateSnapshot_Task, :wait_for_completion)
        expect(redis).to receive(:hset).with('vmpooler__vm__testvm', 'snapshot:testsnapshot', Time.now.to_s)
        expect(logger).to receive(:log)

        subject._create_vm_snapshot('testvm', 'testsnapshot')
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
        expect(pool_helper).to receive(:find_vm).and_return vm_host
        expect(pool_helper).to receive(:find_snapshot).and_return vm_snapshot
        expect(logger).to receive(:log)
        expect(vm_snapshot).to receive_message_chain(:RevertToSnapshot_Task, :wait_for_completion)
        expect(logger).to receive(:log)

        subject._revert_vm_snapshot('testvm', 'testsnapshot')
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

      subject._check_snapshot_queue
    end
  end

end
