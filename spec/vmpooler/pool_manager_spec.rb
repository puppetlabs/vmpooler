require 'spec_helper'
require 'time'

describe 'Vmpooler::PoolManager' do
  let(:logger) { double('logger') }
  let(:redis) { double('redis') }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) { {} }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:default_host) {
    fake_vm = {}
    fake_vm['name'] = 'vm1'
    fake_vm['hostname'] = 'vm1'
    fake_vm['template'] = 'pool1'
    fake_vm['boottime'] = Time.now
    fake_vm['powerstate'] = 'PoweredOn'

    fake_vm
  }
  let(:host) { default_host }
  let(:max_int) { 4611686018427387903 } # A really big integer (64bit)

  subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

  describe '#check_pending_vm' do
    let(:backingservice) { double('backingservice') }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_pending_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_pending_vm).with(vm,pool,timeout,backingservice)

      subject.check_pending_vm(vm, pool, timeout, backingservice)
    end

    it 'calls fail_pending_vm if an error is raised' do
      expect(Thread).to receive(:new).and_yield
      allow(logger).to receive(:log)
      expect(subject).to receive(:_check_pending_vm).with(vm,pool,timeout,backingservice).and_raise('an_error')
      expect(subject).to receive(:fail_pending_vm).with(vm, pool, timeout)

      expect{subject.check_pending_vm(vm, pool, timeout, backingservice)}.to raise_error(/an_error/)
    end

    it 'logs a message if an error is raised' do
      expect(Thread).to receive(:new).and_yield
      expect(logger).to receive(:log)
      expect(subject).to receive(:_check_pending_vm).with(vm,pool,timeout,backingservice).and_raise('an_error')
      allow(subject).to receive(:fail_pending_vm).with(vm, pool, timeout)

      expect{subject.check_pending_vm(vm, pool, timeout, backingservice)}.to raise_error(/an_error/)
    end
  end

  describe '#_check_pending_vm' do
    let(:backingservice) { double('backingservice') }

    before do
      expect(subject).not_to be_nil
    end

    context 'VM does not exist' do
      it 'calls fail_pending_vm' do
        allow(backingservice).to receive(:get_vm).and_return(nil)
        allow(redis).to receive(:hget)
        subject._check_pending_vm(vm, pool, timeout, backingservice)
      end
    end

    context 'VM is in pool and ready' do
      it 'calls move_pending_vm_to_ready' do
        allow(backingservice).to receive(:get_vm).with(vm).and_return(host)
        allow(backingservice).to receive(:is_vm_ready?).with(vm,pool,Integer).and_return(true)
        allow(subject).to receive(:move_pending_vm_to_ready)

        subject._check_pending_vm(vm, pool, timeout, backingservice)
      end
    end

    context 'VM is in pool but not ready' do
      it 'raises an error' do
        allow(backingservice).to receive(:get_vm).with(vm).and_return(host)
        allow(backingservice).to receive(:is_vm_ready?).with(vm,pool,Integer).and_return(false)
        allow(subject).to receive(:move_pending_vm_to_ready)

        expect{subject._check_pending_vm(vm, pool, timeout, backingservice)}.to raise_error(/VM is not ready/)
      end
    end
  end

  describe '#remove_nonexistent_vm' do
    before do
      expect(subject).not_to be_nil
    end

    it 'removes VM from pending in redis' do
      allow(logger).to receive(:log)
      expect(redis).to receive(:srem).with("vmpooler__pending__#{pool}", vm)

      subject.remove_nonexistent_vm(vm, pool)
    end

    it 'logs msg' do
      allow(redis).to receive(:srem)
      expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' no longer exists. Removing from pending.")

      subject.remove_nonexistent_vm(vm, pool)
    end
  end

  describe '#fail_pending_vm' do
    before do
      expect(subject).not_to be_nil
      allow(logger).to receive(:log)
    end

    it 'takes no action if VM is not cloning' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(nil)

      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(true)
    end

    it 'takes no action if VM is within timeout' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(Time.now.to_s)

      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(true)
    end

    it 'moves VM to completed queue if VM has exceeded timeout and exists' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(Date.new(2001,1,1).to_s)
      expect(redis).to receive(:smove).with("vmpooler__pending__#{pool}", "vmpooler__completed__#{pool}", vm)

      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(true)
    end

    it 'logs message if VM has exceeded timeout and exists' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(Date.new(2001,1,1).to_s)
      allow(redis).to receive(:smove)
      expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")

      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(true)
    end

    it 'calls remove_nonexistent_vm if VM has exceeded timeout and does not exist' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(Date.new(2001,1,1).to_s)
      expect(subject).to receive(:remove_nonexistent_vm).with(vm, pool)

      expect(subject.fail_pending_vm(vm, pool, timeout,false)).to eq(true)
    end

    it 'returns false and swallows error if an error is raised' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return('iamnotparsable_asdate')
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(false)
    end

    it 'logs message if an error is raised' do
      expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return('iamnotparsable_asdate')
      expect(logger).to receive(:log).with('d', String)

      subject.fail_pending_vm(vm, pool, timeout,true)
    end
  end

  describe 'move_pending_vm_to_ready' do
    before do
      expect(subject).not_to be_nil
      allow(logger).to receive(:log)
      allow(Socket).to receive(:getaddrinfo)
    end

    context 'when hostname does not match VM name' do
      it 'should not take any action' do
        expect(logger).to receive(:log).exactly(0).times
        expect(Socket).to receive(:getaddrinfo).exactly(0).times

        bad_host = host
        bad_host['hostname'] = 'different_name'

        subject.move_pending_vm_to_ready(vm, pool, bad_host)
      end
    end

    context 'when hostname matches VM name' do
      it 'should use the pool in smove' do
        allow(redis).to receive(:hget)
        allow(redis).to receive(:hset)
        expect(redis).to receive(:smove).with("vmpooler__pending__#{pool}", "vmpooler__ready__#{pool}", vm)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'should log a message' do
        allow(redis).to receive(:hget)
        allow(redis).to receive(:hset)
        allow(redis).to receive(:smove)
        expect(logger).to receive(:log).with('s', "[>] [#{pool}] '#{vm}' moved from 'pending' to 'ready' queue")

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'should use clone start time to determine boot timespan' do
        allow(redis).to receive(:smove)
        expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(Time.now.to_s)
        expect(redis).to receive(:hset).with(String,pool + ':' + vm,String)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'should not determine boot timespan if clone start time not set' do
        allow(redis).to receive(:smove)
        expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return(nil)
        expect(redis).to receive(:hset).with(String,pool + ':' + vm,String).exactly(0).times

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'should raise error if clone start time is not parsable' do
        expect(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'clone').and_return('iamnotparsable_asdate')

        expect{subject.move_pending_vm_to_ready(vm, pool, host)}.to raise_error(/iamnotparsable_asdate/)
      end
    end
  end

  describe '#check_ready_vm' do
    let(:backingservice) { double('backingservice') }
    let (:ttl) { 5 }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_pending_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_ready_vm).with(vm, pool, ttl, backingservice)

      subject.check_ready_vm(vm, pool, ttl, backingservice)
    end

    it 'logs a message if an error is raised' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_ready_vm).with(vm, pool, ttl, backingservice).and_raise('an_error')
      expect(logger).to receive(:log).with('s', "[!] [#{pool}] '#{vm}' failed while checking a ready vm : an_error")

      expect{subject.check_ready_vm(vm, pool, ttl, backingservice)}.to raise_error(/an_error/)
    end
  end





  describe '#_check_ready_vm' do
    let(:backingservice) { double('backingservice') }
    let (:ttl) { 5 }

    let(:config) {
      config = {
        'config': {}
      }
      # Use the configuration defaults
      config[:config]['vm_checktime'] = 15

      config
    }

    before do
      expect(subject).not_to be_nil
      allow(backingservice).to receive(:get_vm).and_return(host)
      allow(logger).to receive(:log)
    end

    context 'a VM that does not need to be checked' do
      it 'should do nothing' do
        allow(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'check').and_return(Time.now.to_s)

        subject._check_ready_vm(vm, pool, ttl, backingservice)
      end
    end

    context 'a VM that does not exist' do
      it 'should log a message' do
        allow(backingservice).to receive(:get_vm).and_return(nil)
        allow(redis).to receive(:srem)
        expect(logger).to receive(:log).with('s', "[!] [#{pool}] '#{vm}' not found in inventory for pool #{pool}, removed from 'ready' queue")

        subject._check_ready_vm(vm, pool, ttl, backingservice)
      end

      it 'should remove the VM from the ready queue' do
        allow(backingservice).to receive(:get_vm).and_return(nil)
        allow(redis).to receive(:srem).with("vmpooler__ready__#{pool}", vm)

        subject._check_ready_vm(vm, pool, ttl, backingservice)
      end
    end

    context 'an old VM' do
      let (:host) {
        fake_vm = default_host
        fake_vm['boottime'] = Time.new(2001,1,1)
        fake_vm
      }

      context 'with a TTL of zero' do
        it 'should do nothing' do
          #allow(backingservice).to receive(:get_vm).and_return(host)
          allow(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'check').and_return(Time.now.to_s)

          subject._check_ready_vm(vm, pool, 0, backingservice)
        end
      end

      context 'with a TTL longer than the VM lifetime' do
        it 'should do nothing' do
         # allow(backingservice).to receive(:get_vm).and_return(host)
          allow(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'check').and_return(Time.now.to_s)

          subject._check_ready_vm(vm, pool, max_int, backingservice)
        end
      end

      context 'with a TTL shorter than the VM lifetime' do
        it 'should move the VM to the completed queue' do
          #allow(backingservice).to receive(:get_vm).and_return(host)
          allow(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'check').and_return(Time.now.to_s)
          expect(redis).to receive(:smove).with("vmpooler__ready__#{pool}", "vmpooler__completed__#{pool}", vm)

          subject._check_ready_vm(vm, pool, 1, backingservice)
        end

        it 'should log a message' do
          #allow(backingservice).to receive(:get_vm).and_return(host)
          allow(redis).to receive(:smove)
          expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{ttl} minutes, removed from 'ready' queue")

          subject._check_ready_vm(vm, pool, ttl, backingservice)
        end
      end
    end

    context 'a VM that has not previously been checked' do
      before do
        allow(redis).to receive(:hget).with("vmpooler__vm__#{vm}", 'check').and_return(nil)
      end

      it 'sets the last check time' do
        expect(redis).to receive(:hset).with("vmpooler__vm__#{vm}", 'check', Time)
        allow(backingservice).to receive(:is_vm_ready?).and_return(true)

        subject._check_ready_vm(vm, pool, ttl, backingservice)
      end

    end

    # TODO Need to test everything inside the check if statement

  end


















  describe '#move_vm_to_ready' do
    before do
      expect(subject).not_to be_nil
    end

    context 'a host without correct summary' do
      it 'does nothing when hostName is nil' do
        host['hostname'] = nil

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when hostName does not match vm' do
        host['hostname'] = 'adifferentvm'

        subject.move_pending_vm_to_ready(vm, pool, host)
      end
    end

    context 'a host with proper summary' do
      before do
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
    let(:backingservice) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
    end

    it 'does nothing with nil host' do
      allow(backingservice).to receive(:get_vm).and_return(nil)
      expect(redis).not_to receive(:smove)
      subject._check_running_vm(vm, pool, timeout, backingservice)
    end

    context 'valid host' do
      let(:vm_host) { double('vmhost') }

      it 'does not move vm when not poweredOn' do
        allow(backingservice).to receive(:get_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOff'

        expect(redis).to receive(:hget)
        expect(redis).not_to receive(:smove)
        expect(logger).not_to receive(:log).with('d', "[!] [#{pool}] '#{vm}' appears to be powered off or dead")

        subject._check_running_vm(vm, pool, timeout, backingservice)
      end

      it 'moves vm when poweredOn, but past TTL' do
        allow(backingservice).to receive(:get_vm).and_return vm_host
        allow(vm_host).to receive(:runtime).and_return true
        allow(vm_host).to receive_message_chain(:runtime, :powerState).and_return 'poweredOn'

        expect(redis).to receive(:hget).with('vmpooler__active__pool1', 'vm1').and_return((Time.now - timeout*60*60).to_s)
        expect(redis).to receive(:smove)
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' reached end of TTL after #{timeout} hours")

        subject._check_running_vm(vm, pool, timeout, backingservice)
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
    let(:backingservice) { {pool => pool_helper} }
    let(:config) { {
      config: { task_limit: 10 },
      pools: [ {'name' => 'pool1', 'size' => 5} ]
    } }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
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
        subject._check_pool(config[:pools][0], backingservice)
      end
    end
  end

  describe '#_stats_running_ready' do
    let(:pool_helper) { double('pool') }
    let(:backingservice) { {pool => pool_helper} }
    let(:metrics) { Vmpooler::DummyStatsd.new }
    let(:config) { {
      config: { task_limit: 10 },
      pools: [ {'name' => 'pool1', 'size' => 5} ],
      graphite: { 'prefix' => 'vmpooler' }
    } }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
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
        subject._check_pool(config[:pools][0], backingservice)
      end

      it 'increments metrics when ready with 0 when pool empty' do
        allow(redis).to receive(:scard).with('vmpooler__ready__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__cloning__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__pending__pool1').and_return(0)
        allow(redis).to receive(:scard).with('vmpooler__running__pool1').and_return(5)

        expect(metrics).to receive(:gauge).with('ready.pool1', 0)
        expect(metrics).to receive(:gauge).with('running.pool1', 5)
        subject._check_pool(config[:pools][0], backingservice)
      end
    end
  end
end
