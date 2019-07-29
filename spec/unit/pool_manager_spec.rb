require 'spec_helper'
require 'time'
require 'mock_redis'

# Custom RSpec :Matchers

# Match a Hashtable['name'] is an expected value
RSpec::Matchers.define :a_pool_with_name_of do |value|
  match { |actual| actual['name'] == value }
end

describe 'Pool Manager' do
  let(:logger) { MockLogger.new }
  let(:redis) { MockRedis.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) { double('host') }
  let(:token) { 'token1234'}

  let(:provider_options) { {} }
  let(:provider) { Vmpooler::PoolManager::Provider::Base.new(config, logger, metrics, 'mock_provider', provider_options) }

  let(:config) { YAML.load(<<-EOT
---
:config: {}
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
EOT
    )
  }

  subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

  describe '#config' do
    before do
      expect(subject).not_to be_nil
    end

    it 'should return the current configuration' do
      expect(subject.config).to eq(config)
    end
  end

  describe '#load_used_providers' do
    let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
    provider: 'spoof'
    EOT
    )
    }
    it do
      files = ["#{project_root_dir}/lib/vmpooler/providers/vsphere.rb",
               "#{project_root_dir}/lib/vmpooler/providers/dummy.rb"]
      expect(subject.load_used_providers).to eq(files)
    end
  end

  it '#default_providers' do
    expect(subject.default_providers).to eq(['vsphere', 'dummy'])
  end

  describe '#check_pending_vm' do
    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_pending_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_pending_vm).with(vm,pool,timeout,provider)

      subject.check_pending_vm(vm, pool, timeout, provider)
    end
  end

  describe '#_check_pending_vm' do
    before do
      expect(subject).not_to be_nil
    end

    context 'host is in pool' do

      it 'calls move_pending_vm_to_ready if host is ready' do
        expect(provider).to receive(:vm_ready?).with(pool,vm).and_return(true)
        expect(subject).to receive(:move_pending_vm_to_ready).with(vm, pool)

        subject._check_pending_vm(vm, pool, timeout, provider)
      end

      it 'calls fail_pending_vm if host is not ready' do
        expect(provider).to receive(:vm_ready?).with(pool,vm).and_return(false)
        expect(subject).to receive(:fail_pending_vm).with(vm, pool, timeout)

        subject._check_pending_vm(vm, pool, timeout, provider)
      end
    end

    context 'with a locked vm mutex' do
      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject).to receive(:vm_mutex).and_return(mutex)

        expect(subject._check_pending_vm(vm, pool, timeout, provider)).to be_nil
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
      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(true)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
    end

    it 'takes no action if VM is within timeout' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Time.now.to_s)
      expect(subject.fail_pending_vm(vm, pool, timeout)).to eq(true)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
    end

    it 'moves VM to completed queue if VM has exceeded timeout and exists' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(true)
      expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(false)
      expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
    end

    it 'logs message if VM has exceeded timeout and exists' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' marked as 'failed' after #{timeout} minutes")
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(true)
    end

    it 'calls remove_nonexistent_vm if VM has exceeded timeout and does not exist' do
      redis.hset("vmpooler__vm__#{vm}", 'clone',Date.new(2001,1,1).to_s)
      expect(subject).to receive(:remove_nonexistent_vm).with(vm, pool)
      expect(subject.fail_pending_vm(vm, pool, timeout,false)).to eq(true)
    end

    it 'swallows error if an error is raised' do
      redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
      expect(subject.fail_pending_vm(vm, pool, timeout,true)).to eq(false)
    end

    it 'logs message if an error is raised' do
      redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
      expect(logger).to receive(:log).with('d', String)

      subject.fail_pending_vm(vm, pool, timeout,true)
    end
  end

  describe '#move_pending_vm_to_ready' do
    let(:host) { { 'hostname' => vm }}

    before do
      expect(subject).not_to be_nil
    end

    before(:each) do
      create_pending_vm(pool,vm)
    end

    context 'when hostname matches VM name' do
      it 'should move the VM from pending to ready pool' do
        expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(true)
        expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(false)
        subject.move_pending_vm_to_ready(vm, pool)
        expect(redis.sismember("vmpooler__pending__#{pool}", vm)).to be(false)
        expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(true)
      end

      it 'should log a message' do
        expect(logger).to receive(:log).with('s', "[>] [#{pool}] '#{vm}' moved from 'pending' to 'ready' queue")

        subject.move_pending_vm_to_ready(vm, pool)
      end

      it 'should receive time_to_ready_state metric' do
        redis.hset("vmpooler__vm__#{vm}", 'clone',Time.now.to_s)
        expect(metrics).to receive(:timing).with(/time_to_ready_state\./,/0/)

        subject.move_pending_vm_to_ready(vm, pool)
      end


      it 'should set the boot time in redis' do
        redis.hset("vmpooler__vm__#{vm}", 'clone',Time.now.to_s)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to be_nil
        subject.move_pending_vm_to_ready(vm, pool)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to_not be_nil
        # TODO Should we inspect the value to see if it's valid?
      end

      it 'should not determine boot timespan if clone start time not set' do
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to be_nil
        subject.move_pending_vm_to_ready(vm, pool)
        expect(redis.hget('vmpooler__boot__' + Date.today.to_s, pool + ':' + vm)).to eq("") # Possible implementation bug here. Should still be nil here
      end

      it 'should raise error if clone start time is not parsable' do
        redis.hset("vmpooler__vm__#{vm}", 'clone','iamnotparsable_asdate')
        expect{subject.move_pending_vm_to_ready(vm, pool)}.to raise_error(/iamnotparsable_asdate/)
      end

      it 'should save the last boot time' do
        expect(redis.hget('vmpooler__lastboot', pool)).to be(nil)
        subject.move_pending_vm_to_ready(vm, pool)
        expect(redis.hget('vmpooler__lastboot', pool)).to_not be(nil)
      end
    end
  end

  describe '#check_ready_vm' do
    let(:ttl) { 0 }
    let(:poolconfig) { config[:pools][0] }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_ready_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_ready_vm).with(vm, poolconfig, ttl, provider)

      subject.check_ready_vm(vm, poolconfig, ttl, provider)
    end
  end

  describe '#_check_ready_vm' do
    let(:ttl) { 0 }
    let(:host) { {} }
    let(:config) { YAML.load(<<-EOT
---
:config: {}
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
:pool_index:
  '#{pool}': 0
EOT
      )
    }

    before(:each) do
      create_ready_vm(pool,vm)
      config[:config]['vm_checktime'] = 15

      # Create a VM which is powered on
      host['hostname'] = vm
      host['powerstate'] = 'PoweredOn'
      allow(provider).to receive(:get_vm).with(pool,vm).and_return(host)
    end

    context 'a VM that does not need to be checked' do
      it 'should do nothing' do
        check_stamp = (Time.now - 60).to_s
        redis.hset("vmpooler__vm__#{vm}", 'check', check_stamp)
        expect(provider).to receive(:get_vm).exactly(0).times
        subject._check_ready_vm(vm, pool, ttl, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'check')).to eq(check_stamp)
      end
    end

    context 'a VM that has never been checked' do
      let(:last_check_date) { Date.new(2001,1,1).to_s }

      it 'should set the current check timestamp' do
        expect(redis.hget("vmpooler__vm__#{vm}", 'check')).to be_nil
        subject._check_ready_vm(vm, pool, ttl, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'check')).to_not be_nil
      end
    end

    context 'a VM that needs to be checked' do
      let(:last_check_date) { Date.new(2001,1,1).to_s }
      before(:each) do
        redis.hset("vmpooler__vm__#{vm}", 'check',last_check_date)
      end

      it 'should set the current check timestamp' do
        expect(redis.hget("vmpooler__vm__#{vm}", 'check')).to eq(last_check_date)
        subject._check_ready_vm(vm, pool, ttl, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'check')).to_not eq(last_check_date)
      end

      context 'and is ready' do
        before(:each) do
          expect(provider).to receive(:vm_ready?).with(pool, vm).and_return(true)
        end

        it 'should only set the next check interval' do
          subject._check_ready_vm(vm, pool, ttl, provider)
        end
      end

      context 'has correct name and is not ready' do
        before(:each) do
          expect(provider).to receive(:vm_ready?).with(pool, vm).and_return(false)
        end

        it 'should move the VM to the completed queue' do
          expect(redis).to receive(:smove).with("vmpooler__ready__#{pool}", "vmpooler__completed__#{pool}", vm)

          subject._check_ready_vm(vm, pool, ttl, provider)
        end

        it 'should move the VM to the completed queue in Redis' do
          expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(true)
          expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(false)
          subject._check_ready_vm(vm, pool, ttl, provider)
          expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(false)
          expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
        end

        it 'should log messages about being unreachable' do
          expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' is unreachable, removed from 'ready' queue")

          subject._check_ready_vm(vm, pool, ttl, provider)
        end
      end

      context 'with hostname mismatch checking enabled' do

        context 'when less than 60 seconds since a VM moved to ready' do
          before(:each) do
            redis.hset("vmpooler__vm__#{vm}", 'ready', Time.now)
          end

          it 'should return nil' do
            expect(subject._check_ready_vm(vm, pool, ttl, provider)).to be_nil
          end
        end

        context 'with a hostname mismatch' do
          let(:different_hostname) { 'different_name' }
          before(:each) do
            expect(provider).to receive(:get_vm).with(pool,vm).and_return(host)
            host['hostname'] = different_hostname
          end

          it 'should move the VM to the completed queue' do
            expect(redis).to receive(:smove).with("vmpooler__ready__#{pool}", "vmpooler__completed__#{pool}", vm)

            subject._check_ready_vm(vm, pool, ttl, provider)
          end

          it 'should move the VM to the completed queue in Redis' do
            expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(true)
            expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(false)
            subject._check_ready_vm(vm, pool, ttl, provider)
            expect(redis.sismember("vmpooler__ready__#{pool}", vm)).to be(false)
            expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
          end

          it 'should log messages about being misnamed' do
            expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' has mismatched hostname #{different_hostname}, removed from 'ready' queue")

            subject._check_ready_vm(vm, pool, ttl, provider)
          end
        end
      end

      context 'with hostname mismatch checking disabled on the pool' do
        before(:each) do
          config[:pools][0]['check_hostname_for_mismatch'] = false
        end

        it 'should not run get_vm' do
          expect(provider).to_not receive(:get_vm)

          subject._check_ready_vm(vm, pool, ttl, provider)
        end
      end

      context 'with hostname mismatch checking disabled in config' do
        before(:each) do
          config[:config]['check_ready_vm_hostname_for_mismatch'] = false
        end

        it 'should not run get_vm' do
          expect(provider).to_not receive(:get_vm)

          subject._check_ready_vm(vm, pool, ttl, provider)
        end
      end
    end

    context 'with a locked vm mutex' do
      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject).to receive(:vm_mutex).and_return(mutex)

        expect(subject._check_ready_vm(vm, pool, ttl, provider)).to be_nil
      end
    end
  end

  describe '#check_running_vm' do
    let(:provider) { double('provider') }
    let (:ttl) { 5 }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _check_running_vm' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_check_running_vm).with(vm, pool, ttl, provider)

      subject.check_running_vm(vm, pool, ttl, provider)
    end
  end

  describe '#_check_running_vm' do
    let(:host) { {} }

    before do
      expect(subject).not_to be_nil
    end

    before(:each) do
      create_running_vm(pool,vm)

      # Create a VM which is powered on
      host['hostname'] = vm
      host['powerstate'] = 'PoweredOn'
      allow(provider).to receive(:get_vm).with(pool,vm).and_return(host)
    end

    it 'moves a missing VM to the completed queue' do
      expect(provider).to receive(:vm_ready?).and_return(false)
      expect(provider).to receive(:get_vm).with(pool,vm).and_return(nil)
      expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
      subject._check_running_vm(vm, pool, timeout, provider)
      expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(false)
    end

    context 'valid host' do
      it 'should not move VM if it has no checkout time' do
        expect(provider).to receive(:vm_ready?).and_return(true)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
        subject._check_running_vm(vm, pool, 0, provider)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
      end

      it 'should not move VM if TTL is zero' do
        expect(provider).to receive(:vm_ready?).and_return(true)
        redis.hset("vmpooler__active__#{pool}", vm,(Time.now - timeout*60*60).to_s)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
        subject._check_running_vm(vm, pool, 0, provider)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
      end

      it 'should move VM when past TTL' do
        redis.hset("vmpooler__active__#{pool}", vm,(Time.now - timeout*60*60).to_s)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(true)
        expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(false)
        subject._check_running_vm(vm, pool, timeout, provider)
        expect(redis.sismember("vmpooler__running__#{pool}", vm)).to be(false)
        expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
      end
    end

    context 'with a locked vm mutex' do
      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject).to receive(:vm_mutex).and_return(mutex)

        expect(subject._check_running_vm(vm, pool, timeout, provider)).to be_nil
      end
    end
  end

  describe '#move_vm_queue' do
    let(:queue_from) { 'pending' }
    let(:queue_to) { 'completed' }
    let(:message) { 'message' }

    before do
      expect(subject).not_to be_nil
    end

    before(:each) do
      create_pending_vm(pool, vm, token)
    end

    it 'VM should be in the "from queue" before the move' do
      expect(redis.sismember("vmpooler__#{queue_from}__#{pool}",vm))
    end

    it 'VM should not be in the "from queue" after the move' do
      subject.move_vm_queue(pool, vm, queue_from, queue_to, message)
      expect(!redis.sismember("vmpooler__#{queue_from}__#{pool}",vm))
    end

    it 'VM should not be in the "to queue" before the move' do
      expect(!redis.sismember("vmpooler__#{queue_to}__#{pool}",vm))
    end

    it 'VM should be in the "to queue" after the move' do
      subject.move_vm_queue(pool, vm, queue_from, queue_to, message)
      expect(redis.sismember("vmpooler__#{queue_to}__#{pool}",vm))
    end

    it 'should log a message' do
      allow(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' #{message}")

      subject.move_vm_queue(pool, vm, queue_from, queue_to, message)
    end
  end

  describe '#clone_vm' do
    let (:pool_object) { { 'name' => pool } }

    before do
      expect(subject).not_to be_nil
      expect(Thread).to receive(:new).and_yield
    end

    it 'calls _clone_vm' do
      expect(subject).to receive(:_clone_vm).with(pool_object,provider)

      subject.clone_vm(pool_object,provider)
    end

    it 'logs a message if an error is raised' do
      allow(logger).to receive(:log)
      expect(logger).to receive(:log).with('s',"[!] [#{pool}] failed while cloning VM with an error: MockError")
      expect(subject).to receive(:_clone_vm).with(pool,provider).and_raise('MockError')

      expect{subject.clone_vm(pool,provider)}.to raise_error(/MockError/)
    end
  end

  describe '#_clone_vm' do
    let (:pool_object) { { 'name' => pool } }
    let (:redis_ttl) { 1 }

    before do
      expect(subject).not_to be_nil
    end

    let(:config) {
      YAML.load(<<-EOT
---
:config:
  prefix: "prefix"
:redis:
  ttl: #{redis_ttl}
EOT
      )
    }

    context 'with no errors during cloning' do
      before(:each) do
        expect(metrics).to receive(:timing).with(/clone\./,/0/)
        expect(provider).to receive(:create_vm).with(pool, String)
        allow(logger).to receive(:log)
      end

      it 'should create a cloning VM' do
        expect(redis.scard("vmpooler__pending__#{pool}")).to eq(0)

        subject._clone_vm(pool,provider)

        expect(redis.scard("vmpooler__pending__#{pool}")).to eq(1)
        # Get the new VM Name from the pending pool queue as it should be the only entry
        vm_name = redis.smembers("vmpooler__pending__#{pool}")[0]
        expect(redis.hget("vmpooler__vm__#{vm_name}", 'clone')).to_not be_nil
        expect(redis.hget("vmpooler__vm__#{vm_name}", 'template')).to eq(pool)
        expect(redis.hget("vmpooler__clone__#{Date.today.to_s}", "#{pool}:#{vm_name}")).to_not be_nil
        expect(redis.hget("vmpooler__vm__#{vm_name}", 'clone_time')).to_not be_nil
      end

      it 'should decrement the clone tasks counter' do
        redis.incr('vmpooler__tasks__clone')
        redis.incr('vmpooler__tasks__clone')
        expect(redis.get('vmpooler__tasks__clone')).to eq('2')
        subject._clone_vm(pool,provider)
        expect(redis.get('vmpooler__tasks__clone')).to eq('1')
      end

      it 'should log a message that is being cloned from a template' do
        expect(logger).to receive(:log).with('d',/\[ \] \[#{pool}\] Starting to clone '(.+)'/)

        subject._clone_vm(pool,provider)
      end

      it 'should log a message that it completed being cloned' do
        expect(logger).to receive(:log).with('s',/\[\+\] \[#{pool}\] '(.+)' cloned in [0-9.]+ seconds/)

        subject._clone_vm(pool,provider)
      end
    end

    context 'with an error during cloning' do
      before(:each) do
        expect(provider).to receive(:create_vm).with(pool, String).and_raise('MockError')
        allow(logger).to receive(:log)
      end

      it 'should not create a cloning VM' do
        expect(redis.scard("vmpooler__pending__#{pool}")).to eq(0)

        expect{subject._clone_vm(pool,provider)}.to raise_error(/MockError/)

        expect(redis.scard("vmpooler__pending__#{pool}")).to eq(0)
        # Get the new VM Name from the pending pool queue as it should be the only entry
        vm_name = redis.smembers("vmpooler__pending__#{pool}")[0]
        expect(vm_name).to be_nil
      end

      it 'should decrement the clone tasks counter' do
        redis.incr('vmpooler__tasks__clone')
        redis.incr('vmpooler__tasks__clone')
        expect(redis.get('vmpooler__tasks__clone')).to eq('2')
        expect{subject._clone_vm(pool,provider)}.to raise_error(/MockError/)
        expect(redis.get('vmpooler__tasks__clone')).to eq('1')
      end

      it 'should expire the vm metadata' do
        expect(redis).to receive(:expire)
        expect{subject._clone_vm(pool,provider)}.to raise_error(/MockError/)
      end

      it 'should raise the error' do
        expect{subject._clone_vm(pool,provider)}.to raise_error(/MockError/)
      end
    end
  end

  describe '#destroy_vm' do
    before do
      expect(subject).not_to be_nil
      expect(Thread).to receive(:new).and_yield
    end

    it 'calls _destroy_vm' do
      expect(subject).to receive(:_destroy_vm).with(vm,pool,provider)

      subject.destroy_vm(vm,pool,provider)
    end

    it 'logs a message if an error is raised' do
      allow(logger).to receive(:log)
      expect(logger).to receive(:log).with('d',"[!] [#{pool}] '#{vm}' failed while destroying the VM with an error: MockError")
      expect(subject).to receive(:_destroy_vm).with(vm,pool,provider).and_raise('MockError')

      expect{subject.destroy_vm(vm,pool,provider)}.to raise_error(/MockError/)
    end
  end

  describe "#_destroy_vm" do
    before(:each) do
      expect(subject).not_to be_nil

      create_completed_vm(vm,pool,true)

      allow(provider).to receive(:destroy_vm).with(pool,vm).and_return(true)

      # Set redis configuration
      config[:redis] = {}
      config[:redis]['data_ttl'] = 168
    end

    context 'when redis data_ttl is not specified in the configuration' do
      before(:each) do
        config[:redis]['data_ttl'] = nil
      end

      it 'should call redis expire with 0' do
        expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to_not be_nil
        subject._destroy_vm(vm,pool,provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to be_nil
      end
    end

    context 'when there is no redis section in the configuration' do
      before(:each) do
        config[:redis] = nil
      end

      it 'should raise an error' do
        expect{ subject._destroy_vm(vm,pool,provider) }.to raise_error(NoMethodError)
      end
    end

    context 'when a VM does not exist' do
      before(:each) do
        # As per base_spec, destroy_vm will return true if the VM does not exist
        expect(provider).to receive(:destroy_vm).with(pool,vm).and_return(true)
      end

      it 'should not raise an error' do
        subject._destroy_vm(vm,pool,provider)
      end
    end

    context 'when the VM is destroyed without error' do
      it 'should log a message the VM was destroyed' do
        expect(logger).to receive(:log).with('s', /\[-\] \[#{pool}\] '#{vm}' destroyed in [0-9.]+ seconds/)
        allow(logger).to receive(:log)

        subject._destroy_vm(vm,pool,provider)
      end

      it 'should emit a timing metric' do
        allow(subject).to receive(:get_vm_usage_labels)
        expect(metrics).to receive(:timing).with("destroy.#{pool}", String)

        subject._destroy_vm(vm,pool,provider)
      end

      it 'should check usage labels' do
        expect(subject).to receive(:get_vm_usage_labels).with(vm)

        subject._destroy_vm(vm,pool,provider)
      end

      it 'should dereference the mutex' do
        expect(subject).to receive(:dereference_mutex)

        subject._destroy_vm(vm,pool,provider)
      end
    end

    context 'when the VM destruction raises an eror' do
      before(:each) do
        # As per base_spec, destroy_vm will return true if the VM does not exist
        expect(provider).to receive(:destroy_vm).with(pool,vm).and_raise('MockError')
      end

      it 'should not log a message the VM was destroyed' do
        expect(logger).to receive(:log).with('s', /\[-\] \[#{pool}\] '#{vm}' destroyed in [0-9.]+ seconds/).exactly(0).times
        allow(logger).to receive(:log)

        expect{ subject._destroy_vm(vm,pool,provider) }.to raise_error(/MockError/)
      end

      it 'should not emit a timing metric' do
        expect(metrics).to receive(:timing).with("destroy.#{pool}", String).exactly(0).times

        expect{ subject._destroy_vm(vm,pool,provider) }.to raise_error(/MockError/)
      end
    end

    context 'when the VM mutex is locked' do
      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject).to receive(:vm_mutex).with(vm).and_return(mutex)

        expect(subject._destroy_vm(vm,pool,provider)).to eq(nil)
      end
    end
  end

  describe '#get_vm_usage_labels' do

    let(:template) { 'pool1' }
    let(:user) { 'vmpuser' }
    let(:vm) { 'vm1' }

    context 'when label evaluation is disabled' do
      it 'should do nothing' do
        subject.get_vm_usage_labels(vm)
      end
    end

    context 'when label evaluation is enabled' do

      before(:each) do
        config[:config]['usage_stats'] = true
      end

      context 'when a VM has not been checked out' do
        before(:each) do
          create_ready_vm(template, vm)
        end

        it 'should return' do
          expect(subject).to receive(:get_vm_usage_labels).and_return(nil)

          subject.get_vm_usage_labels(vm)
        end
      end

      context 'when a VM has been checked out' do

        context 'without auth' do

          before(:each) do
            create_running_vm(template, vm)
          end

          it 'should emit a metric' do
            expect(metrics).to receive(:increment).with("usage.unauthenticated.#{template}")

            subject.get_vm_usage_labels(vm)
          end
        end

        context 'with auth' do

          before(:each) do
            create_running_vm(template, vm, token, user)
          end

          it 'should emit a metric' do
            expect(metrics).to receive(:increment).with("usage.#{user}.#{template}")

            subject.get_vm_usage_labels(vm)
          end

          context 'with a user with period in name' do
            let(:user) { 'test.user'.gsub('.', '_') }
            let(:metric_string) { "usage.#{user}.#{template}" }
            let(:metric_nodes) { metric_string.split('.') }

            before(:each) do
              create_running_vm(template, vm)
            end

            it 'should emit a metric with the character replaced' do
              expect(metrics).to receive(:increment).with(metric_string)

              subject.get_vm_usage_labels(vm)
            end

            it 'should include three nodes' do
              expect(metric_nodes.count).to eq(3)
            end

          end

          context 'with a jenkins_build_url label' do
            let(:jenkins_build_url) { 'https://jenkins.example.com/job/enterprise_pe-acceptance-tests_integration-system_pe_full-agent-upgrade_weekend_2018.1.x/LAYOUT=centos6-64mcd-ubuntu1404-32f-64f,LEGACY_AGENT_VERSION=NONE,PLATFORM=NOTUSED,SCM_BRANCH=2018.1.x,UPGRADE_FROM=2018.1.0,UPGRADE_TO_VERSION=NONE,label=beaker/222/' }
            let(:url_parts) { jenkins_build_url.split('/')[2..-1] }
            let(:instance) { url_parts[0] }
            let(:value_stream_parts) { url_parts[2].split('_') }
            let(:value_stream) { value_stream_parts.shift }
            let(:branch) { value_stream_parts.pop }
            let(:project) { value_stream_parts.shift }
            let(:job_name) { value_stream_parts.join('_') }
            let(:metric_string_nodes) {
              [
                'usage', user, instance, value_stream, branch, project, job_name, template
              ]
            }
            let(:metric_string_sub) {
              metric_string_nodes.map { |s| s.gsub('.', '_')
              }
            }
            let(:metric_string) { metric_string_sub.join('.') }

            before(:each) do
              create_tag(vm, 'jenkins_build_url', jenkins_build_url)
            end

            it 'should emit a metric with information from the URL' do
              expect(metrics).to receive(:increment).with(metric_string)

              subject.get_vm_usage_labels(vm)
            end
          end

          context 'with a jenkins_build_url that contains RMM_COMPONENT_TO_TEST_NAME' do
            let(:jenkins_build_url) { 'https://jenkins.example.com/job/platform_puppet-agent-extra_puppet-agent-integration-suite_pr/RMM_COMPONENT_TO_TEST_NAME=puppet,SLAVE_LABEL=beaker,TEST_TARGET=redhat7-64a/824/' }
            let(:url_parts) { jenkins_build_url.split('/')[2..-1] }
            let(:instance) { url_parts[0].gsub('.', '_') }
            let(:value_stream_parts) { url_parts[2].split('_') }
            let(:value_stream) { value_stream_parts.shift }
            let(:branch) { value_stream_parts.pop }
            let(:project) { value_stream_parts.shift }
            let(:job_name) { value_stream_parts.join('_') }
            let(:build_metadata) { url_parts[3] }
            let(:build_component) { subject.component_to_test('RMM_COMPONENT_TO_TEST_NAME', build_metadata) }
            let(:expected_string) { "usage.#{user}.#{instance}.#{value_stream}.#{branch}.#{project}.#{job_name}.#{build_component}.#{template}" }
            let(:metric_nodes) { expected_string.split('.') }

            before(:each) do
              create_tag(vm, 'jenkins_build_url', jenkins_build_url)
            end

            it 'should emit a metric with information from the URL' do
              expect(metrics).to receive(:increment).with(expected_string)

              subject.get_vm_usage_labels(vm)
            end

            it 'should contain exactly nine nodes' do
              expect(metric_nodes.count).to eq(9)
            end

            context 'when there is no matrix job information' do

              let(:jenkins_build_url) { 'https://jenkins.example.com/job/platform_puppet-agent-extra_puppet-agent-integration-suite_pr/824/' }
              let(:url_parts) { jenkins_build_url.split('/')[2..-1] }
              let(:instance) { url_parts[0].gsub('.', '_') }
              let(:value_stream_parts) { url_parts[2].split('_') }
              let(:value_stream) { value_stream_parts.shift }
              let(:branch) { value_stream_parts.pop }
              let(:project) { value_stream_parts.shift }
              let(:job_name) { value_stream_parts.join('_') }

              before(:each) do
                create_tag(vm, 'jenkins_build_url', jenkins_build_url)
              end

              it 'should emit a metric with information from the URL without a build_component' do
                expect(metrics).to receive(:increment).with("usage.#{user}.#{instance}.#{value_stream}.#{branch}.#{project}.#{job_name}.#{template}")

                subject.get_vm_usage_labels(vm)
              end
            end
          end

        end
      end
    end
  end

  describe '#component_to_test' do
    let(:matching_key) { 'LABEL_ONE' }
    let(:matching_value) { 'test' }
    let(:labels_string) { "#{matching_key}=#{matching_value},LABEL_TWO=test2,LABEL_THREE=test3" }
    let(:nonmatrix_string) { 'test,stuff,and,things' }

    context 'when string contains a matching key' do
      it 'should print the corresponding value' do
        expect(subject.component_to_test(matching_key, labels_string)).to eq(matching_value)
      end

      context 'when match contains no value' do
        it 'should return nil' do
          expect(subject.component_to_test(matching_key, matching_key)).to be nil
        end
      end
    end

    context 'when string contains no key value pairs' do
      it 'should return' do
        expect(subject.component_to_test(matching_key, nonmatrix_string)).to be nil
      end
    end

    context 'when labels_string is a job number' do
      it 'should return nil' do
        expect(subject.component_to_test(matching_key, '25')).to be nil
      end
    end

    context 'when labels_string is nil' do
      it 'should return nil' do
        expect(subject.component_to_test(matching_key, nil)).to be nil
      end
    end
  end

  describe '#purge_unused_vms_and_folders' do
    let(:config) { YAML.load(<<-EOT
---
:config: {}
:providers:
  :mock: {}
:pools:
  - name: '#{pool}'
    size: 1
EOT
      )
    }

    it 'should return when purging is not enabled' do
      expect(subject.purge_unused_vms_and_folders).to be_nil
    end

    context 'with purging enabled globally' do
      before(:each) do
        config[:config]['purge_unconfigured_folders'] = true
        expect(Thread).to receive(:new).and_yield
      end

      it 'should run a purge for each provider' do
        expect(subject).to receive(:purge_vms_and_folders)

        subject.purge_unused_vms_and_folders
      end

      it 'should log when purging fails' do
        expect(subject).to receive(:purge_vms_and_folders).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('s', '[!] failed while purging provider mock VMs and folders with an error: MockError')

        subject.purge_unused_vms_and_folders
      end
    end

    context 'with purging enabled on the provider' do
      before(:each) do
        config[:providers][:mock]['purge_unconfigured_folders'] = true
        expect(Thread).to receive(:new).and_yield
      end

      it 'should run a purge for the provider' do
        expect(subject).to receive(:purge_vms_and_folders)

        subject.purge_unused_vms_and_folders
      end
    end
  end

  describe '#pool_folders' do
    let(:folder_name) { 'myinstance' }
    let(:folder_base) { 'vmpooler' }
    let(:folder) { [folder_base,folder_name].join('/') }
    let(:datacenter) { 'dc1' }
    let(:provider_name) { 'mock_provider' }
    let(:expected_response) {
      {
        folder_name => "#{datacenter}/vm/#{folder_base}"
      }
    }
    let(:config) { YAML.load(<<-EOT
---
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    folder: '#{folder}'
    size: 1
    datacenter: '#{datacenter}'
    provider: '#{provider_name}'
  - name: '#{pool}2'
    folder: '#{folder}'
    size: 1
    datacenter: '#{datacenter}'
    provider: '#{provider_name}2'
EOT
      )
    }

    it 'should return a list of pool folders' do
      expect(provider).to receive(:get_target_datacenter_from_config).with(pool).and_return(datacenter)

      expect(subject.pool_folders(provider)).to eq(expected_response)
    end

    it 'should raise an error when the provider fails to get the datacenter' do
      expect(provider).to receive(:get_target_datacenter_from_config).with(pool).and_raise('mockerror')

      expect{ subject.pool_folders(provider) }.to raise_error(RuntimeError, 'mockerror')
    end
  end

  describe '#purge_vms_and_folders' do
    let(:folder_name) { 'myinstance' }
    let(:folder_base) { 'vmpooler' }
    let(:datacenter) { 'dc1' }
    let(:full_folder_path) { "#{datacenter}/vm/folder_base" }
    let(:configured_folders) { { folder_name => full_folder_path } }
    let(:base_folders) { [ full_folder_path ] }
    let(:folder) { [folder_base,folder_name].join('/') }
    let(:provider_name) { 'mock_provider' }
    let(:whitelist) { nil }
    let(:config) { YAML.load(<<-EOT
---
:config: {}
:providers:
  :mock_provider: {}
:pools:
  - name: '#{pool}'
    folder: '#{folder}'
    size: 1
    datacenter: '#{datacenter}'
    provider: '#{provider_name}'
EOT
      )
    }

    it 'should run purge_unconfigured_folders' do
      expect(subject).to receive(:pool_folders).and_return(configured_folders)
      expect(provider).to receive(:purge_unconfigured_folders).with(base_folders, configured_folders, whitelist)

      subject.purge_vms_and_folders(provider)
    end

    it 'should raise any errors' do
      expect(subject).to receive(:pool_folders).and_return(configured_folders)
      expect(provider).to receive(:purge_unconfigured_folders).with(base_folders, configured_folders, whitelist).and_raise('mockerror')

      expect{ subject.purge_vms_and_folders(provider) }.to raise_error(RuntimeError, 'mockerror')
    end
  end

  describe '#create_vm_disk' do
    let(:provider) { double('provider') }
    let(:disk_size) { 15 }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _create_vm_disk' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_create_vm_disk).with(pool, vm, disk_size, provider)

      subject.create_vm_disk(pool, vm, disk_size, provider)
    end
  end

  describe "#_create_vm_disk" do
    let(:disk_size) { '15' }

    before(:each) do
      expect(subject).not_to be_nil
      allow(logger).to receive(:log)

      create_running_vm(pool,vm,token)
    end

    context 'Given a VM that does not exist' do
      before(:each) do
        # As per base_spec, create_disk will raise if the VM does not exist
        expect(provider).to receive(:create_disk).with(pool,vm,disk_size.to_i).and_raise("VM #{vm} does not exist")
      end

      it 'should not update redis if the VM does not exist' do
        expect(redis).to receive(:hset).exactly(0).times
        expect{ subject._create_vm_disk(pool, vm, disk_size, provider) }.to raise_error(RuntimeError)
      end
    end

    context 'Given an invalid disk size' do
      [{ :description => 'is nil',                            :value => nil },
       { :description => 'is an empty string',                :value => '' },
       { :description => 'is less than 1',                    :value => '0' },
       { :description => 'cannot be converted to an integer', :value => 'abc123' },
      ].each do |testcase|
        it "should not attempt the create the disk if the disk size #{testcase[:description]}" do
          expect(provider).to receive(:create_disk).exactly(0).times
          expect{ subject._create_vm_disk(pool, vm, testcase[:value], provider) }.to raise_error(/Invalid disk size/)
        end
      end

      it 'should raise an error if the disk size is a Fixnum' do
        expect(redis).to receive(:hset).exactly(0).times
        expect{ subject._create_vm_disk(pool, vm, 10, provider) }.to raise_error(NoMethodError,/empty?/)
      end
    end

    context 'Given a successful disk creation' do
      before(:each) do
        expect(provider).to receive(:create_disk).with(pool,vm,disk_size.to_i).and_return(true)
      end

      it 'should log a message' do
        expect(logger).to receive(:log).with('s', "[ ] [disk_manager] '#{vm}' is attaching a #{disk_size}gb disk")
        expect(logger).to receive(:log).with('s', /\[\+\] \[disk_manager\] '#{vm}' attached #{disk_size}gb disk in 0.[\d]+ seconds/)

        subject._create_vm_disk(pool, vm, disk_size, provider)
      end

      it 'should update redis information when attaching the first disk' do
        subject._create_vm_disk(pool, vm, disk_size, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'disk')).to eq("+#{disk_size}gb")
      end

      it 'should update redis information when attaching the additional disks' do
        initial_disks = '+10gb:+20gb'
        redis.hset("vmpooler__vm__#{vm}", 'disk', initial_disks)

        subject._create_vm_disk(pool, vm, disk_size, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'disk')).to eq("#{initial_disks}:+#{disk_size}gb")
      end
    end

    context 'Given a failed disk creation' do
      before(:each) do
        expect(provider).to receive(:create_disk).with(pool,vm,disk_size.to_i).and_return(false)
      end

      it 'should not update redis information' do
        expect(redis).to receive(:hset).exactly(0).times

        subject._create_vm_disk(pool, vm, disk_size, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", 'disk')).to be_nil
      end

      it 'should log a message' do
        expect(logger).to receive(:log).with('s', "[+] [disk_manager] '#{vm}' failed to attach disk")

        subject._create_vm_disk(pool, vm, disk_size, provider)
      end
    end
  end

  describe '#create_vm_snapshot' do
    let(:snapshot_name) { 'snapshot' }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _create_vm_snapshot' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_create_vm_snapshot).with(pool, vm, snapshot_name, provider)

      subject.create_vm_snapshot(pool, vm, snapshot_name, provider)
    end
  end

  describe '#_create_vm_snapshot' do
    let(:snapshot_name) { 'snapshot1' }

    before do
      expect(subject).not_to be_nil
    end

    before(:each) do
      create_running_vm(pool,vm,token)
    end

    context 'Given a Pool that does not exist' do
      let(:missing_pool) { 'missing_pool' }

      before(:each) do
        expect(provider).to receive(:create_snapshot).with(missing_pool, vm, snapshot_name).and_raise("Pool #{missing_pool} not found")
      end

      it 'should not update redis' do
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
        expect{ subject._create_vm_snapshot(missing_pool, vm, snapshot_name, provider) }.to raise_error("Pool #{missing_pool} not found")
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
      end
    end

    context 'Given a VM that does not exist' do
      let(:missing_vm) { 'missing_vm' }
      before(:each) do
        expect(provider).to receive(:create_snapshot).with(pool, missing_vm, snapshot_name).and_raise("VM #{missing_vm} not found")
      end

      it 'should not update redis' do
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
        expect{ subject._create_vm_snapshot(pool, missing_vm, snapshot_name, provider) }.to raise_error("VM #{missing_vm} not found")
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
      end
    end

    context 'Given a snapshot creation that succeeds' do
      before(:each) do
        expect(provider).to receive(:create_snapshot).with(pool, vm, snapshot_name).and_return(true)
      end

      it 'should log messages' do
        expect(logger).to receive(:log).with('s', "[ ] [snapshot_manager] 'Attempting to snapshot #{vm} in pool #{pool}")
        expect(logger).to receive(:log).with('s', /\[\+\] \[snapshot_manager\] '#{vm}' snapshot created in 0.[\d]+ seconds/)

        subject._create_vm_snapshot(pool, vm, snapshot_name, provider)
      end

      it 'should add snapshot redis information' do
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
        subject._create_vm_snapshot(pool, vm, snapshot_name, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to_not be_nil
      end
    end

    context 'Given a snapshot creation that fails' do
      before(:each) do
        expect(provider).to receive(:create_snapshot).with(pool, vm, snapshot_name).and_return(false)
      end

      it 'should log messages' do
        expect(logger).to receive(:log).with('s', "[ ] [snapshot_manager] 'Attempting to snapshot #{vm} in pool #{pool}")
        expect(logger).to receive(:log).with('s', "[+] [snapshot_manager] Failed to snapshot '#{vm}'")

        subject._create_vm_snapshot(pool, vm, snapshot_name, provider)
      end

      it 'should not update redis' do
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
        subject._create_vm_snapshot(pool, vm, snapshot_name, provider)
        expect(redis.hget("vmpooler__vm__#{vm}", "snapshot:#{snapshot_name}")).to be_nil
      end
    end
  end

  describe '#revert_vm_snapshot' do
    let(:snapshot_name) { 'snapshot' }

    before do
      expect(subject).not_to be_nil
    end

    it 'calls _revert_vm_snapshot' do
      expect(Thread).to receive(:new).and_yield
      expect(subject).to receive(:_revert_vm_snapshot).with(pool, vm, snapshot_name, provider)

      subject.revert_vm_snapshot(pool, vm, snapshot_name, provider)
    end
  end

  describe '#_revert_vm_snapshot' do
    let(:snapshot_name) { 'snapshot1' }

    before do
      expect(subject).not_to be_nil
    end

    context 'Given a Pool that does not exist' do
      let(:missing_pool) { 'missing_pool' }

      before(:each) do
        expect(provider).to receive(:revert_snapshot).with(missing_pool, vm, snapshot_name).and_raise("Pool #{missing_pool} not found")
      end

      it 'should not log a result message' do
        expect(logger).to receive(:log).with('s', /\[\+\] \[snapshot_manager\] '#{vm}' reverted to snapshot '#{snapshot_name}' in 0.[\d]+ seconds/).exactly(0).times
        expect(logger).to receive(:log).with('s', "[+] [snapshot_manager] Failed to revert #{vm}' in pool #{missing_pool} to snapshot '#{snapshot_name}'").exactly(0).times

        expect{ subject._revert_vm_snapshot(missing_pool, vm, snapshot_name, provider) }.to raise_error("Pool #{missing_pool} not found")
      end
    end

    context 'Given a VM that does not exist' do
      let(:missing_vm) { 'missing_vm' }
      before(:each) do
        expect(provider).to receive(:revert_snapshot).with(pool, missing_vm, snapshot_name).and_raise("VM #{missing_vm} not found")
      end

      it 'should not log a result message' do
        expect(logger).to receive(:log).with('s', /\[\+\] \[snapshot_manager\] '#{missing_vm}' reverted to snapshot '#{snapshot_name}' in 0.[\d]+ seconds/).exactly(0).times
        expect(logger).to receive(:log).with('s', "[+] [snapshot_manager] Failed to revert #{missing_vm}' in pool #{pool} to snapshot '#{snapshot_name}'").exactly(0).times

        expect{ subject._revert_vm_snapshot(pool, missing_vm, snapshot_name, provider) }.to raise_error("VM #{missing_vm} not found")
      end
    end

    context 'Given a snapshot revert that succeeds' do
      before(:each) do
        expect(provider).to receive(:revert_snapshot).with(pool, vm, snapshot_name).and_return(true)
      end

      it 'should log success messages' do
        expect(logger).to receive(:log).with('s', "[ ] [snapshot_manager] 'Attempting to revert #{vm}' in pool #{pool} to snapshot '#{snapshot_name}'")
        expect(logger).to receive(:log).with('s', /\[\+\] \[snapshot_manager\] '#{vm}' reverted to snapshot '#{snapshot_name}' in 0.[\d]+ seconds/)

        subject._revert_vm_snapshot(pool, vm, snapshot_name, provider)
      end

      it 'should return true' do
        expect(subject._revert_vm_snapshot(pool, vm, snapshot_name, provider)).to be true
      end
    end

    context 'Given a snapshot creation that fails' do
      before(:each) do
        expect(provider).to receive(:revert_snapshot).with(pool, vm, snapshot_name).and_return(false)
      end

      it 'should log failure messages' do
        expect(logger).to receive(:log).with('s', "[ ] [snapshot_manager] 'Attempting to revert #{vm}' in pool #{pool} to snapshot '#{snapshot_name}'")
        expect(logger).to receive(:log).with('s', "[+] [snapshot_manager] Failed to revert #{vm}' in pool #{pool} to snapshot '#{snapshot_name}'")

        subject._revert_vm_snapshot(pool, vm, snapshot_name, provider)
      end

      it 'should return false' do
        expect(subject._revert_vm_snapshot(pool, vm, snapshot_name, provider)).to be false
      end
    end
  end

  describe '#get_pool_name_for_vm' do
    context 'Given a valid VM' do
      before(:each) do
        create_running_vm(pool, vm, token)
      end

      it 'should return the pool name' do
        expect(subject.get_pool_name_for_vm(vm)).to eq(pool)
      end
    end

    context 'Given an invalid VM' do
      it 'should return nil' do
        expect(subject.get_pool_name_for_vm('does_not_exist')).to be_nil
      end
    end
  end

  describe '#get_provider_for_pool' do
    let(:provider_name) { 'mock_provider' }

    before do
      expect(subject).not_to be_nil
      # Inject mock provider into global variable - Note this is a code smell
      $providers = { provider_name => provider }
    end

    after(:each) do
      # Reset the global variable - Note this is a code smell
      $providers = nil
    end

    context 'Given a pool name which does not exist' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
EOT
      )}

      it 'should return nil' do
        expect(subject.get_provider_for_pool('pool_does_not_exist')).to be_nil
      end
    end

    context 'Given a pool which does not have a provider' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
EOT
      )}

      it 'should return nil' do
        expect(subject.get_provider_for_pool(pool)).to be_nil
      end
    end

    context 'Given a pool which uses an invalid provider' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
    provider: 'does_not_exist'
EOT
      )}

      it 'should return nil' do
        expect(subject.get_provider_for_pool(pool)).to be_nil
      end
    end

    context 'Given a pool which uses a valid provider' do
      let(:config) { YAML.load(<<-EOT
---
:config:
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
    provider: #{provider_name}
EOT
      )}

      it 'should return a provider object' do
        result = subject.get_provider_for_pool(pool)
        expect(result).to_not be_nil
        expect(result.name).to eq(provider_name)
      end
    end
  end

  describe '#check_disk_queue' do
    let(:threads) {[]}

    before(:each) do
      expect(Thread).to receive(:new).and_yield
      allow(subject).to receive(:_check_disk_queue)
    end

    it 'should log the disk manager is starting' do
      expect(logger).to receive(:log).with('d', "[*] [disk_manager] starting worker thread")

      expect($threads.count).to be(0)
      subject.check_disk_queue(1,0)
      expect($threads.count).to be(1)
    end

    it 'should add the manager to the global thread list' do
      # Note - Ruby core types are not necessarily thread safe
      expect($threads.count).to be(0)
      subject.check_disk_queue(1,0)
      expect($threads.count).to be(1)
    end

    it 'should call _check_disk_queue' do
      expect(subject).to receive(:_check_disk_queue).with(no_args)

      subject.check_disk_queue(1,0)
    end

    context 'delays between loops' do
      let(:maxloop) { 2 }
      let(:loop_delay) { 1 }
      # Note a maxloop of zero can not be tested as it never terminates

      it 'defaults to 5 second loop delay' do
        expect(subject).to receive(:sleep).with(5).exactly(maxloop).times
        subject.check_disk_queue(maxloop)
      end

      it 'when a non-default loop delay is specified' do
        expect(subject).to receive(:sleep).with(loop_delay).exactly(maxloop).times

        subject.check_disk_queue(maxloop,loop_delay)
      end
    end

    context 'loops specified number of times (5)' do
      let(:maxloop) { 5 }
      # Note a maxloop of zero can not be tested as it never terminates

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      it 'should call _check_disk_queue 5 times' do
        expect(subject).to receive(:_check_disk_queue).with(no_args).exactly(maxloop).times

        subject.check_disk_queue(maxloop,0)
      end
    end
  end

  describe '#_check_disk_queue' do
    before do
      expect(subject).not_to be_nil
    end

    context 'when no VMs in the queue' do
      it 'should not call create_vm_disk' do
        expect(subject).to receive(:create_vm_disk).exactly(0).times
        subject._check_disk_queue
      end
    end

    context 'when VM in the queue does not exist' do
      before(:each) do
        disk_task_vm(vm,"snapshot_#{vm}")
      end

      it 'should log an error' do
        expect(logger).to receive(:log).with('s', /Unable to determine which pool #{vm} is a member of/)

        subject._check_disk_queue
      end

      it 'should not call create_vm_disk' do
        expect(subject).to receive(:create_vm_disk).exactly(0).times

        subject._check_disk_queue
      end
    end

    context 'when specified provider does not exist' do
      before(:each) do
        disk_task_vm(vm,"snapshot_#{vm}")
        create_running_vm(pool, vm, token)
        expect(subject).to receive(:get_provider_for_pool).and_return(nil)
      end

      it 'should log an error' do
        expect(logger).to receive(:log).with('s', /Missing Provider for/)

        subject._check_disk_queue
      end

      it 'should not call create_vm_disk' do
        expect(subject).to receive(:create_vm_disk).exactly(0).times

        subject._check_disk_queue
      end
    end

    context 'when multiple VMs in the queue' do
      before(:each) do
        ['vm1', 'vm2', 'vm3'].each do |vm_name|
          disk_task_vm(vm_name,"snapshot_#{vm_name}")
          create_running_vm(pool, vm_name, token)
        end

        allow(subject).to receive(:get_provider_for_pool).with(pool).and_return(provider)
      end

      it 'should call create_vm_disk once' do
        expect(subject).to receive(:create_vm_disk).exactly(1).times
        subject._check_disk_queue
      end

      it 'should create the disk for the first VM in the queue' do
        expect(subject).to receive(:create_vm_disk).with(pool,'vm1','snapshot_vm1',provider)
        subject._check_disk_queue
      end

      it 'should log an error if one occurs' do
        expect(subject).to receive(:create_vm_disk).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('s', "[!] [disk_manager] disk creation appears to have failed: MockError")
        subject._check_disk_queue
      end
    end
  end

  describe '#check_snapshot_queue' do
    let(:threads) {[]}

    before(:each) do
      expect(Thread).to receive(:new).and_yield
      allow(subject).to receive(:_check_snapshot_queue).with(no_args)
    end

    it 'should log the snapshot manager is starting' do
      expect(logger).to receive(:log).with('d', "[*] [snapshot_manager] starting worker thread")

      expect($threads.count).to be(0)
      subject.check_snapshot_queue(1,0)
      expect($threads.count).to be(1)
    end

    it 'should add the manager to the global thread list' do
      # Note - Ruby core types are not necessarily thread safe
      expect($threads.count).to be(0)
      subject.check_snapshot_queue(1,0)
      expect($threads.count).to be(1)
    end

    it 'should call _check_snapshot_queue' do
      expect(subject).to receive(:_check_snapshot_queue).with(no_args)

      subject.check_snapshot_queue(1,0)
    end

    context 'delays between loops' do
      let(:maxloop) { 2 }
      let(:loop_delay) { 1 }
      # Note a maxloop of zero can not be tested as it never terminates

      it 'defaults to 5 second loop delay' do
        expect(subject).to receive(:sleep).with(5).exactly(maxloop).times
        subject.check_snapshot_queue(maxloop)
      end

      it 'when a non-default loop delay is specified' do
        expect(subject).to receive(:sleep).with(loop_delay).exactly(maxloop).times

        subject.check_snapshot_queue(maxloop,loop_delay)
      end
    end

    context 'loops specified number of times (5)' do
      let(:maxloop) { 5 }
      # Note a maxloop of zero can not be tested as it never terminates

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      it 'should call _check_snapshot_queue 5 times' do
        expect(subject).to receive(:_check_snapshot_queue).with(no_args).exactly(maxloop).times

        subject.check_snapshot_queue(maxloop,0)
      end
    end
  end

  describe '#_check_snapshot_queue' do
    before do
      expect(subject).not_to be_nil
    end

    context 'vmpooler__tasks__snapshot queue' do
      context 'when no VMs in the queue' do
        it 'should not call create_vm_snapshot' do
          expect(subject).to receive(:create_vm_snapshot).exactly(0).times
          subject._check_snapshot_queue
        end
      end

      context 'when VM in the queue does not exist' do
        before(:each) do
          snapshot_vm(vm,"snapshot_#{vm}")
        end

        it 'should log an error' do
          expect(logger).to receive(:log).with('s', /Unable to determine which pool #{vm} is a member of/)

          subject._check_snapshot_queue
        end

        it 'should not call create_vm_snapshot' do
          expect(subject).to receive(:create_vm_snapshot).exactly(0).times

          subject._check_snapshot_queue
        end
      end

      context 'when specified provider does not exist' do
        before(:each) do
          snapshot_vm(vm,"snapshot_#{vm}")
          create_running_vm(pool, vm, token)
          expect(subject).to receive(:get_provider_for_pool).and_return(nil)
        end

        it 'should log an error' do
          expect(logger).to receive(:log).with('s', /Missing Provider for/)

          subject._check_snapshot_queue
        end

        it 'should not call create_vm_snapshot' do
          expect(subject).to receive(:create_vm_snapshot).exactly(0).times

          subject._check_snapshot_queue
        end
      end

      context 'when multiple VMs in the queue' do
        before(:each) do
          ['vm1', 'vm2', 'vm3'].each do |vm_name|
            snapshot_vm(vm_name,"snapshot_#{vm_name}")
            create_running_vm(pool, vm_name, token)
          end

          allow(subject).to receive(:get_provider_for_pool).with(pool).and_return(provider)
        end

        it 'should call create_vm_snapshot once' do
          expect(subject).to receive(:create_vm_snapshot).exactly(1).times
          subject._check_snapshot_queue
        end

        it 'should snapshot the first VM in the queue' do
          expect(subject).to receive(:create_vm_snapshot).with(pool,'vm1','snapshot_vm1',provider)
          subject._check_snapshot_queue
        end

        it 'should log an error if one occurs' do
          expect(subject).to receive(:create_vm_snapshot).and_raise(RuntimeError,'MockError')
          expect(logger).to receive(:log).with('s', "[!] [snapshot_manager] snapshot create appears to have failed: MockError")
          subject._check_snapshot_queue
        end
      end
    end

    context 'vmpooler__tasks__snapshot-revert queue' do
      context 'when no VMs in the queue' do
        it 'should not call revert_vm_snapshot' do
          expect(subject).to receive(:revert_vm_snapshot).exactly(0).times
          subject._check_snapshot_queue
        end
      end

      context 'when VM in the queue does not exist' do
        before(:each) do
          snapshot_revert_vm(vm,"snapshot_#{vm}")
        end

        it 'should log an error' do
          expect(logger).to receive(:log).with('s', /Unable to determine which pool #{vm} is a member of/)

          subject._check_snapshot_queue
        end

        it 'should not call revert_vm_snapshot' do
          expect(subject).to receive(:revert_vm_snapshot).exactly(0).times

          subject._check_snapshot_queue
        end
      end

      context 'when specified provider does not exist' do
        before(:each) do
          snapshot_revert_vm(vm,"snapshot_#{vm}")
          create_running_vm(pool, vm, token)
          expect(subject).to receive(:get_provider_for_pool).and_return(nil)
        end

        it 'should log an error' do
          expect(logger).to receive(:log).with('s', /Missing Provider for/)

          subject._check_snapshot_queue
        end

        it 'should not call revert_vm_snapshot' do
          expect(subject).to receive(:revert_vm_snapshot).exactly(0).times

          subject._check_snapshot_queue
        end
      end

      context 'when multiple VMs in the queue' do
        before(:each) do
          ['vm1', 'vm2', 'vm3'].each do |vm_name|
            snapshot_revert_vm(vm_name,"snapshot_#{vm_name}")
            create_running_vm(pool, vm_name, token)
          end

          allow(subject).to receive(:get_provider_for_pool).with(pool).and_return(provider)
        end

        it 'should call revert_vm_snapshot once' do
          expect(subject).to receive(:revert_vm_snapshot).exactly(1).times
          subject._check_snapshot_queue
        end

        it 'should snapshot the first VM in the queue' do
          expect(subject).to receive(:revert_vm_snapshot).with(pool,'vm1','snapshot_vm1',provider)
          subject._check_snapshot_queue
        end

        it 'should log an error if one occurs' do
          expect(subject).to receive(:revert_vm_snapshot).and_raise(RuntimeError,'MockError')
          expect(logger).to receive(:log).with('s', "[!] [snapshot_manager] snapshot revert appears to have failed: MockError")
          subject._check_snapshot_queue
        end
      end
    end
  end

  describe '#migrate_vm' do
    before(:each) do
      expect(subject).not_to be_nil
      expect(Thread).to receive(:new).and_yield
    end

    it 'calls migrate_vm' do
      expect(provider).to receive(:migrate_vm).with(pool, vm)

      subject.migrate_vm(vm, pool, provider)
    end

    context 'When an error is raised' do
      before(:each) do
        expect(provider).to receive(:migrate_vm).with(pool, vm).and_raise('MockError')
      end

      it 'logs a message' do
        allow(logger).to receive(:log)
        expect(logger).to receive(:log).with('s', "[x] [#{pool}] '#{vm}' migration failed with an error: MockError")

        subject.migrate_vm(vm, pool, provider)
      end
    end

    context 'with a locked vm mutex' do
      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject).to receive(:vm_mutex).and_return(mutex)

        expect(subject.migrate_vm(vm, pool, provider)).to be_nil
      end
    end
  end

  describe '#vm_mutex' do
    it 'should return a mutex' do
      expect(subject.vm_mutex(vm)).to be_a(Mutex)
    end

    it 'should return the same mutex when called twice' do
      first = subject.vm_mutex(vm)
      second = subject.vm_mutex(vm)
      expect(first).to be(second)
    end
  end

  describe '#dereference_mutex' do
    it 'should return nil when no mutex is dereferenced' do
      expect(subject.dereference_mutex(vm)).to be_nil
    end

    it 'should return true when a mutex is dereferenced' do
      subject.vm_mutex(vm)
      expect(subject.dereference_mutex(vm)).to be true
    end

    it 'should dereference the mutex' do
      mutex = subject.vm_mutex(vm)

      subject.dereference_mutex(vm)

      result = subject.vm_mutex(vm)
      expect(result).to_not eq(mutex)
    end
  end

  describe 'sync_pool_template' do
    let(:old_template) { 'templates/old-template' }
    let(:new_template) { 'templates/new-template' }
    let(:config) { YAML.load(<<-EOT
---
:pools:
  - name: '#{pool}'
    size: 1
    template: old_template
EOT
      )
    }

    it 'returns when a template is not set in redis' do
      expect(subject.sync_pool_template(config[:pools][0])).to be_nil
    end

    it 'returns when a template is set and matches the configured template' do
      redis.hset('vmpooler__config__template', pool, old_template)

      subject.sync_pool_template(config[:pools][0])

      expect(config[:pools][0]['template']).to eq(old_template)
    end

    it 'updates a pool template when the redis provided value is different' do
      redis.hset('vmpooler__config__template', pool, new_template)

      subject.sync_pool_template(config[:pools][0])

      expect(config[:pools][0]['template']).to eq(new_template)
    end
  end

  describe 'pool_mutex' do
    it 'should return a mutex' do
      expect(subject.pool_mutex(pool)).to be_a(Mutex)
    end

    it 'should return the same mutex when called twice' do
      first = subject.pool_mutex(pool)
      second = subject.pool_mutex(pool)
      expect(first).to be(second)
    end
  end

  describe 'update_pool_template' do
    let(:current_template) { 'templates/pool_template' }
    let(:new_template) { 'templates/new_pool_template' }
    let(:config) {
      YAML.load(<<-EOT
---
:config: {}
:pools:
  - name: #{pool}
    template: "#{current_template}"
EOT
      )
    }
    let(:poolconfig) { config[:pools][0] }

    before(:each) do
      allow(logger).to receive(:log)
    end

    it 'should set the pool template to match the configured template' do
      subject.update_pool_template(poolconfig, provider, new_template, current_template)

      expect(poolconfig['template']).to eq(new_template)
    end

    it 'should log that the template is updated' do
      expect(logger).to receive(:log).with('s', "[*] [#{pool}] template updated from #{current_template} to #{new_template}")

      subject.update_pool_template(poolconfig, provider, new_template, current_template)
    end

    it 'should run drain_pool' do
      expect(subject).to receive(:drain_pool).with(pool)

      subject.update_pool_template(poolconfig, provider, new_template, current_template)
    end

    it 'should log that a template is being prepared' do
      expect(logger).to receive(:log).with('s', "[*] [#{pool}] preparing pool template for deployment")

      subject.update_pool_template(poolconfig, provider, new_template, current_template)
    end

    it 'should run prepare_template' do
      expect(subject).to receive(:prepare_template).with(poolconfig, provider)

      subject.update_pool_template(poolconfig, provider, new_template, current_template)
    end

    it 'should log that the pool is ready for use' do
      expect(logger).to receive(:log).with('s', "[*] [#{pool}] is ready for use")

      subject.update_pool_template(poolconfig, provider, new_template, current_template)
    end
  end

  describe '#remove_excess_vms' do
    let(:config) {
      YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    size: 2
EOT
      )
    }

    before(:each) do
      expect(subject).not_to be_nil
    end

    context 'with a 0 total value' do
      let(:ready) { 0 }
      let(:total) { 0 }
      it 'should return nil' do
        expect(subject.remove_excess_vms(config[:pools][0])).to be_nil
      end
    end

    context 'when the mutex is locked' do
      let(:mutex) { Mutex.new }
      before(:each) do
        expect(redis).to receive(:scard).with("vmpooler__pending__#{pool}").and_return(1)
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(2)
        mutex.lock
        expect(subject).to receive(:pool_mutex).with(pool).and_return(mutex)
      end

      it 'should return nil' do
        expect(subject.remove_excess_vms(config[:pools][0])).to be_nil
      end
    end

    context 'with a total size less than the pool size' do
      it 'should return nil' do
        expect(redis).to receive(:scard).with("vmpooler__pending__#{pool}").and_return(1)
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(1)
        expect(subject.remove_excess_vms(config[:pools][0])).to be_nil
      end
    end

    context 'with a total size greater than the pool size' do
      it 'should remove excess ready vms' do
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(4)
        expect(redis).to receive(:scard).with("vmpooler__pending__#{pool}").and_return(0)
        expect(subject).to receive(:move_vm_queue).exactly(2).times

        subject.remove_excess_vms(config[:pools][0])
      end

      it 'should remove excess pending vms' do
        create_pending_vm(pool,'vm1')
        create_pending_vm(pool,'vm2')
        create_ready_vm(pool, 'vm3')
        create_ready_vm(pool, 'vm4')
        create_ready_vm(pool, 'vm5')
        expect(subject).to receive(:move_vm_queue).exactly(3).times

        subject.remove_excess_vms(config[:pools][0])
      end
    end
  end

  describe 'prepare_template' do
    let(:config) { YAML.load(<<-EOT
---
:config:
  create_template_delta_disks: true
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
    template: 'templates/pool1'
EOT
      )
    }

    context 'when creating the template delta disks' do
      before(:each) do
        allow(redis).to receive(:hset)
        allow(provider).to receive(:create_template_delta_disks)
      end

      it 'should run create template delta disks' do
        expect(provider).to receive(:create_template_delta_disks).with(config[:pools][0])

        subject.prepare_template(config[:pools][0], provider)
      end

      it 'should mark the template as prepared' do
        expect(redis).to receive(:hset).with('vmpooler__template__prepared', pool, config[:pools][0]['template'])

        subject.prepare_template(config[:pools][0], provider)
      end
    end

    context 'when template delta disk creation fails' do
      before(:each) do
        allow(redis).to receive(:hset)
        expect(provider).to receive(:create_template_delta_disks).and_raise("MockError")
      end

      it 'should log a message when delta disk creation returns an error' do
        expect(logger).to receive(:log).with('s', "[!] [#{pool}] failed while preparing a template with an error. As a result vmpooler could not create the template delta disks. Either a template delta disk already exists, or the template delta disk creation failed. The error is: MockError")

        subject.prepare_template(config[:pools][0], provider)
      end
    end
  end

  describe 'evaluate_template' do
    let(:mutex) { Mutex.new }
    let(:current_template) { 'templates/template1' }
    let(:new_template) { 'templates/template2' }
    let(:config) { YAML.load(<<-EOT
---
:config:
  task_limit: 5
:providers:
  :mock:
:pools:
  - name: '#{pool}'
    size: 1
    template: '#{current_template}'
EOT
      )
    }

    before(:each) do
      allow(redis).to receive(:hget)
      expect(subject).to receive(:pool_mutex).with(pool).and_return(mutex)
    end

    it 'should retreive the prepared template' do
      expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).and_return(current_template)

      subject.evaluate_template(config[:pools][0], provider)
    end

    it 'should retrieve the redis configured template' do
      expect(redis).to receive(:hget).with('vmpooler__config__template', pool).and_return(new_template)

      subject.evaluate_template(config[:pools][0], provider)
    end

    context 'when the mutex is locked' do
      before(:each) do
        mutex.lock
      end

      it 'should return' do
        expect(subject.evaluate_template(config[:pools][0], provider)).to be_nil
      end
    end

    context 'when prepared template is nil' do

      it 'should prepare the template' do
        expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).and_return(nil)
        expect(subject).to receive(:prepare_template).with(config[:pools][0], provider)

        subject.evaluate_template(config[:pools][0], provider)
      end

      it 'should not prepare the template again' do
        expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).and_return(current_template)
        expect(subject).to_not receive(:prepare_template).with(config[:pools][0], provider)

        subject.evaluate_template(config[:pools][0], provider)
      end
    end

    context 'when the configured pool template does not match the prepared template' do
      before(:each) do
        config[:pools][0]['template'] = new_template
        expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).and_return(current_template)
      end

      it 'should prepare the template' do
        expect(subject).to receive(:prepare_template).with(config[:pools][0], provider)

        subject.evaluate_template(config[:pools][0], provider)
      end

      context 'if configured_template is provided' do
        it 'should not run prepare_template' do
          expect(redis).to receive(:hget).with('vmpooler__config__template', pool).and_return(current_template)
          expect(subject).to_not receive(:prepare_template)

          subject.evaluate_template(config[:pools][0], provider)
        end
      end
    end

    context 'when a new template is requested' do
      before(:each) do
        expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).and_return(current_template)
        expect(redis).to receive(:hget).with('vmpooler__config__template', pool).and_return(new_template)
      end

      it 'should update the template' do
        expect(subject).to receive(:update_pool_template).with(config[:pools][0], provider, new_template, current_template)

        subject.evaluate_template(config[:pools][0], provider)
      end
    end
  end

  describe 'drain_pool' do
    before(:each) do
      allow(logger).to receive(:log)
    end

    context 'with no vms' do
      it 'should return nil' do
        expect(subject.drain_pool(pool)).to be_nil
      end

      it 'should not log any messages' do
        expect(logger).to_not receive(:log)

        subject.drain_pool(pool)
      end

      it 'should not try to move any vms' do
        expect(subject).to_not receive(:move_vm_queue)

        subject.drain_pool(pool)
      end
    end

    context 'with ready vms' do
      before(:each) do
        create_ready_vm(pool, 'vm1')
        create_ready_vm(pool, 'vm2')
      end

      it 'removes the ready instances' do
        expect(subject).to receive(:move_vm_queue).twice

        subject.drain_pool(pool)
      end

      it 'logs that ready instances are being removed' do
        expect(logger).to receive(:log).with('s', "[*] [#{pool}] removing ready instances")

        subject.drain_pool(pool)
      end
    end

    context 'with pending instances' do
      before(:each) do
        create_pending_vm(pool, 'vm1')
        create_pending_vm(pool, 'vm2')
      end

      it 'removes the pending instances' do
        expect(subject).to receive(:move_vm_queue).twice

        subject.drain_pool(pool)
      end

      it 'logs that pending instances are being removed' do
        expect(logger).to receive(:log).with('s', "[*] [#{pool}] removing pending instances")

        subject.drain_pool(pool)
      end
    end
  end

  describe 'update_pool_size' do
    let(:newsize) { '3' }
    let(:config) {
      YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    size: 2
EOT
      )
    }
    let(:poolconfig) { config[:pools][0] }

    context 'with a locked mutex' do

      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
        expect(subject).to receive(:pool_mutex).with(pool).and_return(mutex)
      end

      it 'should return nil' do
        expect(subject.update_pool_size(poolconfig)).to be_nil
      end
    end

    it 'should get the pool size configuration from redis' do
      expect(redis).to receive(:hget).with('vmpooler__config__poolsize', pool)

      subject.update_pool_size(poolconfig)
    end

    it 'should return when poolsize is not set in redis' do
      expect(redis).to receive(:hget).with('vmpooler__config__poolsize', pool).and_return(nil)

      expect(subject.update_pool_size(poolconfig)).to be_nil
    end

    it 'should return when no change in configuration is required' do
      expect(redis).to receive(:hget).with('vmpooler__config__poolsize', pool).and_return('2')

      expect(subject.update_pool_size(poolconfig)).to be_nil
    end

    it 'should update the pool size' do
      expect(redis).to receive(:hget).with('vmpooler__config__poolsize', pool).and_return(newsize)

      subject.update_pool_size(poolconfig)

      expect(poolconfig['size']).to eq(Integer(newsize))
    end
  end

  describe 'update_clone_target' do
    let(:newtarget) { 'cluster2' }
    let(:config) {
      YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    clone_target: 'cluster1'
EOT
      )
    }
    let(:poolconfig) { config[:pools][0] }

    context 'with a locked mutex' do

      let(:mutex) { Mutex.new }
      before(:each) do
        mutex.lock
        expect(subject).to receive(:pool_mutex).with(pool).and_return(mutex)
      end

      it 'should return nil' do
        expect(subject.update_clone_target(poolconfig)).to be_nil
      end
    end

    it 'should get the pool clone target configuration from redis' do
      expect(redis).to receive(:hget).with('vmpooler__config__clone_target', pool)

      subject.update_clone_target(poolconfig)
    end

    it 'should return when clone_target is not set in redis' do
      expect(redis).to receive(:hget).with('vmpooler__config__clone_target', pool).and_return(nil)

      expect(subject.update_clone_target(poolconfig)).to be_nil
    end

    it 'should return when no change in configuration is required' do
      expect(redis).to receive(:hget).with('vmpooler__config__clone_target', pool).and_return('cluster1')

      expect(subject.update_clone_target(poolconfig)).to be_nil
    end

    it 'should update the clone target' do
      expect(redis).to receive(:hget).with('vmpooler__config__clone_target', pool).and_return(newtarget)

      subject.update_clone_target(poolconfig)

      expect(poolconfig['clone_target']).to eq(newtarget)
    end
  end

  describe "#execute!" do
    let(:config) {
      YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
EOT
      )
    }

    before(:each) do
      expect(subject).not_to be_nil

      allow(subject).to receive(:check_disk_queue)
      allow(subject).to receive(:check_snapshot_queue)
      allow(subject).to receive(:check_pool)

      allow(logger).to receive(:log)
    end

    after(:each) do
      # Reset the global variable - Note this is a code smell
      $threads = nil
    end

    context 'on startup' do
      it 'should log a message that VMPooler has started' do
        expect(logger).to receive(:log).with('d', 'starting vmpooler')

        subject.execute!(1,0)
      end

      it 'should set clone tasks to zero' do
        redis.set('vmpooler__tasks__clone', 1)
        subject.execute!(1,0)
        expect(redis.get('vmpooler__tasks__clone')).to eq('0')
      end

      it 'should clear migration tasks' do
        redis.set('vmpooler__migration', 1)
        subject.execute!(1,0)
        expect(redis.get('vmpooler__migration')).to be_nil
      end

      it 'should run the check_disk_queue method' do
        expect(subject).to receive(:check_disk_queue)

        subject.execute!(1,0)
      end

      it 'should run the check_snapshot_queue method' do
        expect(subject).to receive(:check_snapshot_queue)

        subject.execute!(1,0)
      end

      it 'should check the pools in the config' do
        expect(subject).to receive(:check_pool).with(a_pool_with_name_of(pool))

        subject.execute!(1,0)
      end

      context 'creating Providers' do
        let(:vsphere_provider) { double('vsphere_provider') }
        let(:config) {
        YAML.load(<<-EOT
---
:providers:
  :vsphere: {}
:pools:
  - name: #{pool}
  - name: 'dummy'
    provider: 'vsphere'
EOT
        )}

        it 'should call create_provider_object idempotently' do
          # Even though there are two pools using the vsphere provider (the default), it should only
          # create the provider object once.
          expect(subject).to receive(:create_provider_object).with(Object, Object, Object, 'vsphere', 'vsphere', Object).and_return(vsphere_provider)

          subject.execute!(1,0)
        end

        it 'should raise an error if the provider can not be created' do
          expect(subject).to receive(:create_provider_object).and_raise(RuntimeError, "MockError")

          expect{ subject.execute!(1,0) }.to raise_error(/MockError/)
        end

        it 'should log a message if the provider can not be created' do
          expect(subject).to receive(:create_provider_object).and_raise(RuntimeError, "MockError")
          expect(logger).to receive(:log).with('s',"Error while creating provider for pool #{pool}: MockError")

          expect{ subject.execute!(1,0) }.to raise_error(/MockError/)
        end
      end
    end

    context 'creating multiple vsphere Providers' do
      let(:vsphere_provider) { double('vsphere_provider') }
      let(:vsphere_provider2) { double('vsphere_provider') }
      let(:provider1) { Vmpooler::PoolManager::Provider::Base.new(config, logger, metrics, 'vsphere', provider_options) }
      let(:provider2) { Vmpooler::PoolManager::Provider::Base.new(config, logger, metrics, 'secondvsphere', provider_options) }
      let(:config) {
        YAML.load(<<-EOT
---
:providers:
  :vsphere:
    server: 'blah1'
    provider_class: 'vsphere'
  :secondvsphere:
    server: 'blah2'
    provider_class: 'vsphere'
:pools:
  - name: #{pool}
    provider: 'vsphere'
  - name: 'secondpool'
    provider: 'secondvsphere'
EOT
        )}

      it 'should call create_provider_object twice' do
        # The two pools use a different provider name, but each provider_class is vsphere
        expect(subject).to receive(:create_provider_object).with(Object, Object, Object, "vsphere", "vsphere", Object).and_return(vsphere_provider)
        expect(subject).to receive(:create_provider_object).with(Object, Object, Object, "vsphere", "secondvsphere", Object).and_return(vsphere_provider2)
        subject.execute!(1,0)
      end

      it 'should have vsphere providers with different servers' do
        allow(subject).to receive(:get_provider_for_pool).with(pool).and_return(provider1)
        result = subject.get_provider_for_pool(pool)
        allow(provider1).to receive(:provider_config).and_call_original
        expect(result.provider_config['server']).to eq('blah1')

        allow(subject).to receive(:get_provider_for_pool).with('secondpool').and_return(provider2)
        result = subject.get_provider_for_pool('secondpool')
        allow(provider1).to receive(:provider_config).and_call_original
        expect(result.provider_config['server']).to eq('blah2')
        subject.execute!(1,0)
      end
    end

    context 'modify configuration on startup' do
      context 'move vSphere configuration to providers location' do
        let(:config) {
        YAML.load(<<-EOT
:vsphere:
  server: 'vsphere.example.com'
  username: 'vmpooler'
  password: 'password'
:pools:
  - name: #{pool}
EOT
        )}

        it 'should set providers with no provider to vsphere' do
          expect(subject.config[:providers]).to be nil

          subject.execute!(1,0)
          expect(subject.config[:providers][:vsphere]['server']).to eq('vsphere.example.com')
          expect(subject.config[:providers][:vsphere]['username']).to eq('vmpooler')
          expect(subject.config[:providers][:vsphere]['password']).to eq('password')
        end

        it 'should log a message' do
          expect(logger).to receive(:log).with('d', "[!] Detected an older configuration file. Copying the settings from ':vsphere:' to ':providers:/:vsphere:'")

          subject.execute!(1,0)
        end
      end


      context 'default to the vphere provider' do
        let(:config) {
        YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
  - name: 'dummy'
    provider: 'dummy'
EOT
        )}

        it 'should set providers with no provider to vsphere' do
          expect(subject.config[:pools][0]['provider']).to be_nil
          expect(subject.config[:pools][1]['provider']).to eq('dummy')

          subject.execute!(1,0)

          expect(subject.config[:pools][0]['provider']).to eq('vsphere')
          expect(subject.config[:pools][1]['provider']).to eq('dummy')
        end

        it 'should log a message' do
          expect(logger).to receive(:log).with('d', "[!] Setting provider for pool '#{pool}' to 'vsphere' as default")

          subject.execute!(1,0)
        end
      end
    end

    context 'with dead disk_manager thread' do
      let(:disk_manager_thread) { double('thread', :alive? => false) }

      before(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = {}
        $threads['disk_manager'] = disk_manager_thread
      end

      it 'should run the check_disk_queue method and log a message' do
        expect(subject).to receive(:check_disk_queue)
        expect(logger).to receive(:log).with('d', "[!] [disk_manager] worker thread died, restarting")

        subject.execute!(1,0)
      end
    end

    context 'with dead snapshot_manager thread' do
      let(:snapshot_manager_thread) { double('thread', :alive? => false) }
      before(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = {}
        $threads['snapshot_manager'] = snapshot_manager_thread
      end

      it 'should run the check_snapshot_queue method and log a message' do
        expect(subject).to receive(:check_snapshot_queue)
        expect(logger).to receive(:log).with('d', "[!] [snapshot_manager] worker thread died, restarting")
        $threads['snapshot_manager'] = snapshot_manager_thread

        subject.execute!(1,0)
      end
    end

    context 'with dead pool thread' do
      context 'without check_loop_delay_xxx settings' do
        let(:pool_thread) { double('thread', :alive? => false) }
        let(:default_check_loop_delay_min) { 5 }
        let(:default_check_loop_delay_max) { 60 }
        let(:default_check_loop_delay_decay) { 2.0 }
        before(:each) do
          # Reset the global variable - Note this is a code smell
          $threads = {}
          $threads[pool] = pool_thread
        end

        it 'should run the check_pool method and log a message' do
          expect(subject).to receive(:check_pool).with(a_pool_with_name_of(pool),
                                                       default_check_loop_delay_min,
                                                       default_check_loop_delay_max,
                                                       default_check_loop_delay_decay)
          expect(logger).to receive(:log).with('d', "[!] [#{pool}] worker thread died, restarting")

          subject.execute!(1,0)
        end
      end

      context 'with check_loop_delay_xxx settings' do
        let(:pool_thread) { double('thread', :alive? => false) }
        let(:check_loop_delay_min) { 7 }
        let(:check_loop_delay_max) { 20 }
        let(:check_loop_delay_decay) { 2.1 }

        let(:config) {
      YAML.load(<<-EOT
---
:config:
  check_loop_delay_min: #{check_loop_delay_min}
  check_loop_delay_max: #{check_loop_delay_max}
  check_loop_delay_decay: #{check_loop_delay_decay}
:pools:
  - name: #{pool}
EOT
          )
        }
        before(:each) do
          # Reset the global variable - Note this is a code smell
          $threads = {}
          $threads[pool] = pool_thread
        end

        it 'should run the check_pool method and log a message' do
          expect(subject).to receive(:check_pool).with(a_pool_with_name_of(pool),
                                                       check_loop_delay_min,
                                                       check_loop_delay_max,
                                                       check_loop_delay_decay)
          expect(logger).to receive(:log).with('d', "[!] [#{pool}] worker thread died, restarting")

          subject.execute!(1,0)
        end
      end
    end

    context 'delays between loops' do
      let(:maxloop) { 2 }
      let(:loop_delay) { 1 }
      # Note a maxloop of zero can not be tested as it never terminates
      before(:each) do
  
        allow(subject).to receive(:check_disk_queue)
        allow(subject).to receive(:check_snapshot_queue)
        allow(subject).to receive(:check_pool)
      end

      it 'when a non-default loop delay is specified' do
        expect(subject).to receive(:sleep).with(loop_delay).exactly(maxloop).times

        subject.execute!(maxloop,loop_delay)
      end
    end

    context 'loops specified number of times (5)' do
      let(:alive_thread) { double('thread', :alive? => true) }
      let(:maxloop) { 5 }
      # Note a maxloop of zero can not be tested as it never terminates
      before(:each) do
        end

      it 'should run startup tasks only once' do
        expect(redis).to receive(:set).with('vmpooler__tasks__clone', 0).once
        expect(redis).to receive(:del).with('vmpooler__migration').once

        subject.execute!(maxloop,0)
      end

      it 'should run per thread tasks 5 times when threads are not remembered' do
        expect(subject).to receive(:check_disk_queue).exactly(maxloop).times
        expect(subject).to receive(:check_snapshot_queue).exactly(maxloop).times
        expect(subject).to receive(:check_pool).exactly(maxloop).times

        subject.execute!(maxloop,0)
      end

      it 'should not run per thread tasks when threads are alive' do
        expect(subject).to receive(:check_disk_queue).exactly(0).times
        expect(subject).to receive(:check_snapshot_queue).exactly(0).times
        expect(subject).to receive(:check_pool).exactly(0).times

        $threads[pool] = alive_thread
        $threads['disk_manager'] = alive_thread
        $threads['snapshot_manager'] = alive_thread

        subject.execute!(maxloop,0)
      end
    end
  end

  describe "#sleep_with_wakeup_events" do
    let(:loop_delay) { 10 }
    before(:each) do
      allow(Kernel).to receive(:sleep).and_raise("sleep should not be called")
      allow(subject).to receive(:time_passed?).with(:wakeup_by, Time).and_call_original
      allow(subject).to receive(:time_passed?).with(:exit_by, Time).and_call_original
    end

    it 'should not sleep if the loop delay is negative' do
      expect(subject).to receive(:sleep).exactly(0).times

      subject.sleep_with_wakeup_events(-1)
    end

    it 'should sleep until the loop delay is exceeded' do
      # This test is a little brittle as it requires knowledge of the implementation
      # Basically the number of sleep delays will dictate how often the time_passed? method is called

      expect(subject).to receive(:sleep).exactly(2).times
      expect(subject).to receive(:time_passed?).with(:exit_by, Time).and_return(false, false, false, true)

      subject.sleep_with_wakeup_events(loop_delay)
    end

    describe 'with the pool_size_change wakeup option' do
      let(:wakeup_option) {{
        :pool_size_change => true,
        :poolname => pool,
      }}
      let(:wakeup_period) { -1 } # A negative number forces the wakeup evaluation to always occur

      it 'should check the number of VMs ready in Redis' do
        expect(subject).to receive(:time_passed?).with(:exit_by, Time).and_return(false, true)
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").once

        subject.sleep_with_wakeup_events(loop_delay, wakeup_period, wakeup_option)
      end

      it 'should sleep until the number of VMs ready in Redis increases' do
        expect(subject).to receive(:sleep).exactly(3).times
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(1,1,1,2)

        subject.sleep_with_wakeup_events(loop_delay, wakeup_period, wakeup_option)
      end

      it 'should sleep until the number of VMs ready in Redis decreases' do
        expect(subject).to receive(:sleep).exactly(3).times
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(2,2,2,1)

        subject.sleep_with_wakeup_events(loop_delay, wakeup_period, wakeup_option)
      end
    end

    describe 'with the pool_template_change wakeup option' do
      let(:wakeup_option) {{
        :pool_template_change => true,
        :poolname => pool
      }}
      let(:new_template) { 'templates/newtemplate' }
      let(:wakeup_period) { -1 } # A negative number forces the wakeup evaluation to always occur

      context 'with a template configured' do
        before(:each) do
          redis.hset('vmpooler__config__template', pool, new_template)
          allow(redis).to receive(:hget)
        end

        it 'should check if a template is configured in redis' do
          expect(subject).to receive(:time_passed?).with(:exit_by, Time).and_return(false, true)
          expect(redis).to receive(:hget).with('vmpooler__template__prepared', pool).once

          subject.sleep_with_wakeup_events(loop_delay, wakeup_period, wakeup_option)
        end

        it 'should sleep until a template change is detected' do
          expect(subject).to receive(:sleep).exactly(3).times
          expect(redis).to receive(:hget).with('vmpooler__config__template', pool).and_return(nil,nil,new_template)

          subject.sleep_with_wakeup_events(loop_delay, wakeup_period, wakeup_option)
        end
      end
    end
  end

  describe "#check_pool" do
    let(:threads) {{}}
    let(:provider_name) { 'mock_provider' }
    let(:config) {
      YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    provider: #{provider_name}
EOT
      )
    }

    let(:pool_object) { config[:pools][0] }
    let(:check_pool_response) {{
        :discovered_vms      => 0,
        :checked_running_vms => 0,
        :checked_ready_vms   => 0,
        :checked_pending_vms => 0,
        :destroyed_vms       => 0,
        :migrated_vms        => 0,
        :cloned_vms          => 0,
    }}

    before do
      expect(subject).not_to be_nil
      expect(Thread).to receive(:new).and_yield
      allow(subject).to receive(:get_provider_for_pool).with(pool).and_return(provider)
    end

    context 'on startup' do
      before(:each) do
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
        expect(logger).to receive(:log).with('d', "[*] [#{pool}] starting worker thread")
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      it 'should log a message the worker thread is starting' do
        subject.check_pool(pool_object,1,0)
      end

      it 'should populate the threads global variable' do
        subject.check_pool(pool_object,1,0)

        # Unable to test for nil as the Thread is mocked
        expect($threads.keys.include?(pool))
      end
    end

    context 'delays between loops' do
      let(:maxloop) { 2 }
      let(:loop_delay) { 1 }
      # Note a maxloop of zero can not be tested as it never terminates

      before(:each) do
        allow(logger).to receive(:log)
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      it 'when a non-default loop delay is specified' do
        expect(subject).to receive(:sleep_with_wakeup_events).with(loop_delay, Numeric, Hash).exactly(maxloop).times

        subject.check_pool(pool_object,maxloop,loop_delay,loop_delay)
      end

      it 'specifies a wakeup option for pool size change' do
        expect(subject).to receive(:sleep_with_wakeup_events).with(loop_delay, Numeric, hash_including(:pool_size_change => true)).exactly(maxloop).times

        subject.check_pool(pool_object,maxloop,loop_delay,loop_delay)
      end

      it 'specifies a wakeup option for poolname' do
        expect(subject).to receive(:sleep_with_wakeup_events).with(loop_delay, Numeric, hash_including(:poolname => pool)).exactly(maxloop).times

        subject.check_pool(pool_object,maxloop,loop_delay,loop_delay)
      end
    end

    context 'delays between loops configured in the pool configuration' do
      let(:maxloop) { 2 }
      let(:loop_delay) { 1 }
      let(:pool_loop_delay) { 2 }
      let(:config) {
        YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    provider: #{provider_name}
    check_loop_delay_min: #{pool_loop_delay}
    check_loop_delay_max: #{pool_loop_delay}
EOT
        )
      }

      before(:each) do
        allow(logger).to receive(:log)
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      it 'when a non-default loop delay is specified' do
        expect(subject).to receive(:sleep_with_wakeup_events).with(pool_loop_delay, pool_loop_delay, Hash).exactly(maxloop).times

        subject.check_pool(pool_object,maxloop,loop_delay)
      end
    end

    context 'delays between loops with a specified min and max value' do
      let(:maxloop) { 5 }
      let(:loop_delay_min) { 1 }
      let(:loop_delay_max) { 60 }
      # Note a maxloop of zero can not be tested as it never terminates

      before(:each) do
        allow(logger).to receive(:log)
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      [:checked_pending_vms, :discovered_vms, :cloned_vms].each do |testcase|
        describe "when #{testcase} is greater than zero" do
          it "delays the minimum delay time" do
            expect(subject).to receive(:sleep_with_wakeup_events).with(loop_delay_min, loop_delay_min, Hash).exactly(maxloop).times
            check_pool_response[testcase] = 1

            subject.check_pool(pool_object,maxloop,loop_delay_min,loop_delay_max)
          end
        end
      end

      [:checked_running_vms, :checked_ready_vms, :destroyed_vms, :migrated_vms].each do |testcase|
        describe "when #{testcase} is greater than zero" do
          let(:loop_decay) { 3.0 }
          it "delays increases with a decay" do
            expect(subject).to receive(:sleep_with_wakeup_events).with(3, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(9, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(27, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(60, Numeric, Hash).twice
            check_pool_response[testcase] = 1

            subject.check_pool(pool_object,maxloop,loop_delay_min,loop_delay_max,loop_decay)
          end
        end
      end
    end

    context 'delays between loops with a specified min and max value configured in the pool configuration' do
      let(:maxloop) { 5 }
      let(:loop_delay_min) { 1 }
      let(:loop_delay_max) { 60 }
      let(:loop_decay) { 3.0 }
      let(:pool_loop_delay_min) { 3 }
      let(:pool_loop_delay_max) { 70 }
      let(:pool_loop_delay_decay) { 2.5 }
      let(:config) {
        YAML.load(<<-EOT
---
:pools:
  - name: #{pool}
    provider: #{provider_name}
    check_loop_delay_min: #{pool_loop_delay_min}
    check_loop_delay_max: #{pool_loop_delay_max}
    check_loop_delay_decay: #{pool_loop_delay_decay}
EOT
        )
      }

      before(:each) do
        allow(logger).to receive(:log)
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
      end

      [:checked_pending_vms, :discovered_vms, :cloned_vms].each do |testcase|
        describe "when #{testcase} is greater than zero" do
          it "delays the minimum delay time" do
            expect(subject).to receive(:sleep_with_wakeup_events).with(pool_loop_delay_min, Numeric, Hash).exactly(maxloop).times
            check_pool_response[testcase] = 1

            subject.check_pool(pool_object,maxloop,loop_delay_min,loop_delay_max,loop_decay)
          end
        end
      end

      [:checked_running_vms, :checked_ready_vms, :destroyed_vms, :migrated_vms].each do |testcase|
        describe "when #{testcase} is greater than zero" do
          it "delays increases with a decay" do
            expect(subject).to receive(:sleep_with_wakeup_events).with(7, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(17, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(42, Numeric, Hash).once
            expect(subject).to receive(:sleep_with_wakeup_events).with(70, Numeric, Hash).twice
            check_pool_response[testcase] = 1

            subject.check_pool(pool_object,maxloop,loop_delay_min,loop_delay_max,loop_decay)
          end
        end
      end
    end


    context 'loops specified number of times (5)' do
      let(:maxloop) { 5 }
      # Note a maxloop of zero can not be tested as it never terminates
      before(:each) do
        allow(logger).to receive(:log)
        allow(subject).to receive(:_check_pool).and_return(check_pool_response)
      end

      after(:each) do
        # Reset the global variable - Note this is a code smell
        $threads = nil
        $provider = nil
      end

      it 'should run startup tasks only once' do
        expect(logger).to receive(:log).with('d', "[*] [#{pool}] starting worker thread")

        subject.check_pool(pool_object,maxloop,0)
      end

      it 'should run per thread tasks 5 times' do
        expect(subject).to receive(:_check_pool).exactly(maxloop).times

        subject.check_pool(pool_object,maxloop,0)
      end
    end
  end

  describe '#create_inventory' do

    it 'should log an error if one occurs' do
      allow(provider).to receive(:vms_in_pool).and_raise(
        RuntimeError,'Mock Error'
      )

      expect {
        subject.create_inventory(config[:pools].first, provider, {})
      }.to raise_error(RuntimeError, 'Mock Error')
    end
  end

  describe '#check_running_pool_vms' do
    let(:pool_object) { config[:pools][0] }
    let(:pool_check_response) {
      {:checked_running_vms => 0}
    }
    context 'Running VM not in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {}
      }
      before(:each) do
        create_running_vm(pool,vm,token)
      end

      it 'should not call check_running_vm' do
        expect(subject).to receive(:check_running_vm).exactly(0).times

        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should move the VM to completed queue' do
        expect(subject).to receive(:move_vm_queue).with(pool,vm,'running','completed',String).and_call_original

        subject.check_running_pool_vms(pool,provider, pool_check_response, inventory)
      end
    end

    context 'Running VM in the inventory' do
      let(:provider) { double('provider') }
      let(:inventory) {
        # mock response from create_inventory
        { vm => 1 }
      }
      before(:each) do
        allow(subject).to receive(:check_running_vm)
        create_running_vm(pool,vm,token)
      end

      it 'should log an error if one occurs' do
        expect(subject).to receive(:check_running_vm).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] _check_pool with an error while evaluating running VMs: MockError")

        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should return the number of checked running VMs' do
        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)

        expect(pool_check_response[:checked_running_vms]).to be(1)
      end

      it 'should use the VM lifetime in preference to defaults' do
        big_lifetime = 2000

        redis.hset("vmpooler__vm__#{vm}", 'lifetime',big_lifetime)
        # The lifetime comes in as string
        expect(subject).to receive(:check_running_vm).with(vm,pool,"#{big_lifetime}",provider)

        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should use the configuration default if the VM lifetime is not set' do
        config[:config]['vm_lifetime'] = 50
        expect(subject).to receive(:check_running_vm).with(vm,pool,50,provider)

        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should use a lifetime of 12 if nothing is set' do
        expect(subject).to receive(:check_running_vm).with(vm,pool,12,provider)

        subject.check_running_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end
  end

  describe '#check_ready_pool_vms' do
    let(:provider) { double('provider') }
    let(:pool_check_response) {
      {:checked_ready_vms => 0}
    }

    context 'Ready VM not in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {}
      }
      before(:each) do
        create_ready_vm(pool,vm,token)
      end

      it 'should not call check_ready_vm' do
        expect(subject).to receive(:check_ready_vm).exactly(0).times

        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should move the VM to completed queue' do
        expect(subject).to receive(:move_vm_queue).with(pool,vm,'ready','completed',String).and_call_original

        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end

    context 'Ready VM in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {vm => 1}
      }
      let(:big_lifetime) { 2000 }
      before(:each) do
        allow(subject).to receive(:check_ready_vm)
        create_ready_vm(pool,vm,token)
      end

      it 'should return the number of checked ready VMs' do
        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory)

        expect(pool_check_response[:checked_ready_vms]).to be(1)
      end

      it 'should log an error if one occurs' do
        expect(subject).to receive(:check_ready_vm).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] _check_pool failed with an error while evaluating ready VMs: MockError")

        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory, big_lifetime)
      end

      it 'should use the pool TTL if set' do
        expect(subject).to receive(:check_ready_vm).with(vm,pool,big_lifetime,provider)

        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory, big_lifetime)
      end

      it 'should use a pool TTL of zero if none set' do
        expect(subject).to receive(:check_ready_vm).with(vm,pool,0,provider)

        subject.check_ready_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end
  end

  describe '#check_pending_pool_vms' do
    let(:provider) { double('provider') }
    let(:pool_check_response) {
      {:checked_pending_vms => 0}
    }

    context 'Pending VM not in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {}
      }

      before(:each) do
        create_pending_vm(pool,vm,token)
      end

      it 'should call fail_pending_vm' do
        expect(subject).to receive(:fail_pending_vm).with(vm,pool,Integer,false)

        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end

    context 'Pending VM in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {vm => 1}
      }

      before(:each) do
        create_pending_vm(pool,vm,token)
      end

      it 'should return the number of checked pending VMs' do
        allow(subject).to receive(:check_pending_vm)
        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory)

        expect(pool_check_response[:checked_pending_vms]).to be(1)
      end

      it 'should log an error if one occurs' do
        expect(subject).to receive(:check_pending_vm).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('d', "[!] [#{pool}] _check_pool failed with an error while evaluating pending VMs: MockError")

        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should use the pool timeout if set' do
        big_lifetime = 2000

        config[:pools][0]['timeout'] = big_lifetime
        expect(subject).to receive(:check_pending_vm).with(vm,pool,big_lifetime,provider)

        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory, big_lifetime)
      end

      it 'should use the configuration setting if the pool timeout is not set' do
        big_lifetime = 2000

        config[:config]['timeout'] = big_lifetime
        expect(subject).to receive(:check_pending_vm).with(vm,pool,big_lifetime,provider)

        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should use a pool timeout of 15 if nothing is set' do
        expect(subject).to receive(:check_pending_vm).with(vm,pool,15,provider)

        subject.check_pending_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end
  end

  describe '#check_completed_pool_vms' do
    let(:provider) { double('provider') }
    let(:pool_check_response) { {
        :checked_completed_vms => 0,
        :destroyed_vms => 0
      }
    }
    context 'Completed VM not in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {}
      }

      before(:each) do
        create_completed_vm(vm,pool,true)
      end

      it 'should log a message' do
        subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should not call destroy_vm' do
        expect(subject).to receive(:destroy_vm).exactly(0).times

        subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should remove redis information' do
        expect(redis.sismember("vmpooler__completed__#{pool}",vm)).to be(true)
        expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to_not be(nil)
        expect(redis.hget("vmpooler__active__#{pool}",vm)).to_not be(nil)

        subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)

        expect(redis.sismember("vmpooler__completed__#{pool}",vm)).to be(false)
        expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to be(nil)
        expect(redis.hget("vmpooler__active__#{pool}",vm)).to be(nil)
      end
    end

    context 'Completed VM in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {vm => 1}
      }

      before(:each) do
        create_completed_vm(vm,pool,true)
      end

      it 'should call destroy_vm' do
        expect(subject).to receive(:destroy_vm)

        subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should return the number of destroyed VMs' do
        subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)

        expect(pool_check_response[:destroyed_vms]).to be(1)
      end

      context 'with an error during destroy_vm' do
        before(:each) do
          expect(subject).to receive(:destroy_vm).and_raise(RuntimeError,"MockError")
          expect(logger).to receive(:log).with('d', "[!] [#{pool}] _check_pool failed with an error while evaluating completed VMs: MockError")
        end

        it 'should log a message' do
          subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)
        end

        it 'should remove redis information' do
          expect(redis.sismember("vmpooler__completed__#{pool}",vm)).to be(true)
          expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to_not be(nil)
          expect(redis.hget("vmpooler__active__#{pool}",vm)).to_not be(nil)

          subject.check_completed_pool_vms(pool, provider, pool_check_response, inventory)

          expect(redis.sismember("vmpooler__completed__#{pool}",vm)).to be(false)
          expect(redis.hget("vmpooler__vm__#{vm}", 'checkout')).to be(nil)
          expect(redis.hget("vmpooler__active__#{pool}",vm)).to be(nil)
        end
      end
    end
  end

  describe "#check_discovered_pool_vms" do
    context 'Discovered VM' do
      before(:each) do
        create_discovered_vm(vm,pool)
      end

      it 'should be moved to the completed queue' do
        subject.check_discovered_pool_vms(pool)

        expect(redis.sismember("vmpooler__completed__#{pool}", vm)).to be(true)
      end

      it 'should log a message if an error occurs' do
        expect(redis).to receive(:smove).with("vmpooler__discovered__#{pool}", "vmpooler__completed__#{pool}", vm).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with("d", "[!] [#{pool}] _check_pool failed with an error while evaluating discovered VMs: MockError")

        subject.check_discovered_pool_vms(pool)
      end

      ['pending','ready','running','completed'].each do |queue_name|
        context "exists in the #{queue_name} queue" do
          before(:each) do
            allow(subject).to receive(:migrate_vm)
            allow(subject).to receive(:check_running_vm)
            allow(subject).to receive(:check_ready_vm)
            allow(subject).to receive(:check_pending_vm)
            allow(subject).to receive(:destroy_vm)
            allow(subject).to receive(:clone_vm)
          end

          it "should remain in the #{queue_name} queue" do
            redis.sadd("vmpooler__#{queue_name}__#{pool}", vm)
            allow(logger).to receive(:log)

            subject.check_discovered_pool_vms(pool)

            expect(redis.sismember("vmpooler__#{queue_name}__#{pool}", vm)).to be(true)
          end

          it "should be removed from the discovered queue" do
            redis.sadd("vmpooler__#{queue_name}__#{pool}", vm)
            allow(logger).to receive(:log)

            expect(redis.sismember("vmpooler__discovered__#{pool}", vm)).to be(true)
            subject.check_discovered_pool_vms(pool)
            expect(redis.sismember("vmpooler__discovered__#{pool}", vm)).to be(false)
          end

          it "should log a message" do
            redis.sadd("vmpooler__#{queue_name}__#{pool}", vm)
            expect(logger).to receive(:log).with('d', "[!] [#{pool}] '#{vm}' found in '#{queue_name}', removed from 'discovered' queue")

            subject.check_discovered_pool_vms(pool)
          end
        end
      end
    end
  end

  describe "#check_migrating_pool_vms" do
    let(:provider) { double('provider') }
    let(:pool_check_response) { {
        :migrated_vms => 0
      }
    }

    context 'Migrating VM not in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {}
      }

      before(:each) do
        create_migrating_vm(vm,pool)
      end

      it 'should not do anything' do
        expect(subject).to receive(:migrate_vm).exactly(0).times

        subject.check_migrating_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end

    context 'Migrating VM in the inventory' do
      let(:inventory) {
        # mock response from create_inventory
        {vm => 1}
      }

      before(:each) do
        create_migrating_vm(vm,pool)
      end

      it 'should return the number of migrated VMs' do
        allow(subject).to receive(:migrate_vm).with(vm,pool,provider)
        subject.check_migrating_pool_vms(pool, provider, pool_check_response, inventory)

        expect(pool_check_response[:migrated_vms]).to be(1)
      end

      it 'should log an error if one occurs' do
        expect(subject).to receive(:migrate_vm).and_raise(RuntimeError,'MockError')
        expect(logger).to receive(:log).with('s', "[x] [#{pool}] '#{vm}' failed to migrate: MockError")

        subject.check_migrating_pool_vms(pool, provider, pool_check_response, inventory)
      end

      it 'should call migrate_vm' do
        expect(subject).to receive(:migrate_vm).with(vm,pool,provider)

        subject.check_migrating_pool_vms(pool, provider, pool_check_response, inventory)
      end
    end
  end

  describe '#repopulate_pool_vms' do
    let(:pool_size) { 0 }
    let(:config) {
      YAML.load(<<-EOT
---
:config:
  task_limit: 10
EOT
      )
    }
    let(:provider) { double('provider') }
    let(:pool_check_response) {
      {
        :cloned_vms => 0
      }
    }

    it 'should not call clone_vm when number of VMs is equal to the pool size' do
      expect(subject).to receive(:clone_vm).exactly(0).times

      subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
    end

    it 'should not call clone_vm when number of VMs is greater than the pool size' do
      create_ready_vm(pool,vm,token)
      expect(subject).to receive(:clone_vm).exactly(0).times

      subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
    end

    ['ready','pending'].each do |queue_name|
      it "should use VMs in #{queue_name} queue to calculate pool size" do
        expect(subject).to receive(:clone_vm).exactly(0).times
        # Modify the pool size to 1 and add a VM in the queue
        redis.sadd("vmpooler__#{queue_name}__#{pool}",vm)
        pool_size = 1
  
        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end
    end

    ['running','completed','discovered','migrating'].each do |queue_name|
      it "should not use VMs in #{queue_name} queue to calculate pool size" do
        expect(subject).to receive(:clone_vm)
        # Modify the pool size to 1 and add a VM in the queue
        redis.sadd("vmpooler__#{queue_name}__#{pool}",vm)
        pool_size = 1

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end
    end

    it 'should log a message the first time a pool is empty' do
      expect(logger).to receive(:log).with('s', "[!] [#{pool}] is empty")

      subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
    end

    context 'when pool is marked as empty' do

      before(:each) do
        redis.set("vmpooler__empty__#{pool}", 'true')
      end

      it 'should not log a message when the pool remains empty' do
        expect(logger).to receive(:log).with('s', "[!] [#{pool}] is empty").exactly(0).times

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end

      it 'should remove the empty pool mark if it is no longer empty' do
        create_ready_vm(pool,vm,token)

        expect(redis.get("vmpooler__empty__#{pool}")).to be_truthy
        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
        expect(redis.get("vmpooler__empty__#{pool}")).to be_falsey
      end
    end

    context 'when number of VMs is less than the pool size' do

      it 'should return the number of cloned VMs' do
        pool_size = 5

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)

        expect(pool_check_response[:cloned_vms]).to be(pool_size)
      end

      it 'should call clone_vm to populate the pool' do
        pool_size = 5

        expect(subject).to receive(:clone_vm).exactly(pool_size).times

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end

      it 'should call clone_vm until task_limit is hit' do
        task_limit = 2
        pool_size = 5
        config[:config]['task_limit'] = task_limit

        expect(subject).to receive(:clone_vm).exactly(task_limit).times

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end

      it 'log a message if a cloning error occurs' do
        pool_size = 2

        expect(subject).to receive(:clone_vm).and_raise(RuntimeError,"MockError")
        expect(logger).to receive(:log).with("s", "[!] [#{pool}] clone failed during check_pool with an error: MockError")
        create_ready_vm(pool,'vm')
        expect{ subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size) }.to raise_error(RuntimeError,'MockError')

      end
    end

    context 'when a pool template is updating' do
      let(:poolsize) { 2 }
      let(:mutex) { Mutex.new }
      before(:each) do
        expect(subject).to receive(:pool_mutex).with(pool).and_return(mutex)
        mutex.lock
      end

      it 'should not call clone_vm to populate the pool' do
        expect(subject).to_not receive(:clone_vm)

        subject.repopulate_pool_vms(pool, provider, pool_check_response, poolsize)
      end
    end

    context 'export metrics' do
      it 'increments metrics for ready queue' do
        create_ready_vm(pool,'vm1')
        create_ready_vm(pool,'vm2')
        create_ready_vm(pool,'vm3')

        expect(metrics).to receive(:gauge).with("ready.#{pool}", 3)
        allow(metrics).to receive(:gauge)

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end

      it 'increments metrics for running queue' do
        create_running_vm(pool,'vm1',token)
        create_running_vm(pool,'vm2',token)
        create_running_vm(pool,'vm3',token)

        expect(metrics).to receive(:gauge).with("running.#{pool}", 3)
        allow(metrics).to receive(:gauge)

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end

      it 'increments metrics with 0 when pool empty' do

        expect(metrics).to receive(:gauge).with("ready.#{pool}", 0)
        expect(metrics).to receive(:gauge).with("running.#{pool}", 0)

        subject.repopulate_pool_vms(pool, provider, pool_check_response, pool_size)
      end
    end
  end

  describe '#_check_pool' do
    let(:new_vm_response) {
      # Mock response from Base Provider for vms_in_pool
      [{ 'name' => new_vm}]
    }
    let(:vm_response) {
      # Mock response from Base Provider for vms_in_pool
      [{ 'name' => vm}]
    }
    let(:multi_vm_response) {
      # Mock response from Base Provider for vms_in_pool
      [{ 'name' => 'vm1'},
       { 'name' => 'vm2'},
       { 'name' => 'vm3'}]
    }

    # Default test fixtures will consist of;
    #   - Empty Redis dataset
    #   - A single pool with a pool size of zero i.e. no new VMs should be created
    #   - Task limit of 10
    let(:config) {
      YAML.load(<<-EOT
---
:config:
  task_limit: 10
:pools:
  - name: #{pool}
    size: 10
    ready_ttl: 1234
    timeout: 5678
EOT
      )
    }
    let(:pool_object) { config[:pools][0] }
    let(:new_vm) { 'newvm'}
    let(:pool_name) { pool_object['name'] }
    let(:mutex) { Mutex.new }

    before do
      expect(subject).not_to be_nil
      allow(logger).to receive(:log)
    end

    # INVENTORY
    context 'Conducting inventory' do
      before(:each) do
        allow(subject).to receive(:migrate_vm)
        allow(subject).to receive(:check_running_vm)
        allow(subject).to receive(:check_ready_vm)
        allow(subject).to receive(:check_pending_vm)
        allow(subject).to receive(:destroy_vm)
        allow(subject).to receive(:clone_vm)
        allow(provider).to receive(:vms_in_pool).with(pool).and_return(new_vm_response)
      end

      it 'calls inventory correctly' do
        expect(subject).to receive(:create_inventory)
        subject._check_pool(pool_object, provider)
      end

      it 'captures #create_inventory errors correctly' do
        allow(subject).to receive(:create_inventory).and_raise(RuntimeError,'Mock Error')
        subject._check_pool(pool_object, provider)
      end

      it 'should return early if an error occurs' do
        allow(subject).to receive(:create_inventory).and_raise(
          RuntimeError,'Mock Error'
        )

        expect(subject).to_not receive(:check_running_pool_vms)
        subject._check_pool(pool_object, provider)
      end

      it 'should return that no actions were taken' do
        expect(provider).to receive(:vms_in_pool).and_raise(RuntimeError,'Mock Error')

        result = subject._check_pool(pool_object,provider)

        expect(result[:discovered_vms]).to be(0)
        expect(result[:checked_running_vms]).to be(0)
        expect(result[:checked_ready_vms]).to be(0)
        expect(result[:checked_pending_vms]).to be(0)
        expect(result[:destroyed_vms]).to be(0)
        expect(result[:migrated_vms]).to be(0)
        expect(result[:cloned_vms]).to be(0)
      end

      it 'should log the discovery of VMs' do
        expect(logger).to receive(:log).with('s', "[?] [#{pool}] '#{new_vm}' added to 'discovered' queue")

        subject._check_pool(pool_object,provider)
      end

      it 'should return the number of discovered VMs' do
        result = subject._check_pool(pool_object,provider)

        expect(result[:discovered_vms]).to be(1)
      end

      it 'should add undiscovered VMs to the completed queue' do
        allow(logger).to receive(:log).with('s', "[?] [#{pool}] '#{new_vm}' added to 'discovered' queue")

        expect(redis.sismember("vmpooler__discovered__#{pool}", new_vm)).to be(false)
        expect(redis.sismember("vmpooler__completed__#{pool}", new_vm)).to be(false)

        subject._check_pool(pool_object,provider)

        expect(redis.sismember("vmpooler__discovered__#{pool}", new_vm)).to be(false)
        expect(redis.sismember("vmpooler__completed__#{pool}", new_vm)).to be(true)
      end

      ['running','ready','pending','completed','discovered','migrating'].each do |queue_name|
        it "should not discover VMs in the #{queue_name} queue" do
          expect(logger).to receive(:log).with('s', "[?] [#{pool}] '#{new_vm}' added to 'discovered' queue").exactly(0).times
          expect(redis.sismember("vmpooler__discovered__#{pool}", new_vm)).to be(false)
          redis.sadd("vmpooler__#{queue_name}__#{pool}", new_vm)

          subject._check_pool(pool_object,provider)

          if queue_name == 'discovered'
            # Discovered VMs end up in the completed queue
            expect(redis.sismember("vmpooler__completed__#{pool}", new_vm)).to be(true)
          else
            expect(redis.sismember("vmpooler__#{queue_name}__#{pool}", new_vm)).to be(true)
          end
        end
      end

      it 'should get the pool mutex' do
        expect(subject).to receive(:pool_mutex).and_return(mutex).at_least(:once)

        subject._check_pool(pool_object,provider)
      end

      it 'should run synchronize' do
        expect(subject).to receive(:pool_mutex).and_return(mutex).at_least(:once)
        expect(mutex).to receive(:synchronize).at_least(:once)

        subject._check_pool(pool_object,provider)
      end

      it 'should yield when locked' do
        expect(subject).to receive(:pool_mutex).and_return(mutex).at_least(:once)
        mutex.lock
        expect(mutex).to receive(:synchronize).and_yield

        subject._check_pool(pool_object,provider)
      end
    end

    # RUNNING
    context 'when checking running VMs' do
      let(:pool_check_response) {
        {
          discovered_vms: 0,
          checked_running_vms: 0,
          checked_ready_vms: 0,
          checked_pending_vms: 0,
          destroyed_vms: 0,
          migrated_vms: 0,
          cloned_vms: 0
        }
      }

      it 'should call #check_running_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_running_pool_vms).with(pool, provider, pool_check_response, {})

        subject._check_pool(pool_object,provider)
      end
    end

    # READY
    context 'when checking ready VMs' do
      let(:pool_check_response) {
        {
          discovered_vms: 0,
          checked_running_vms: 0,
          checked_ready_vms: 0,
          checked_pending_vms: 0,
          destroyed_vms: 0,
          migrated_vms: 0,
          cloned_vms: 0
        }
      }

      it 'should call #check_ready_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_ready_pool_vms).with(pool, provider, pool_check_response, {}, pool_object['ready_ttl'])

        subject._check_pool(pool_object,provider)
      end
    end

    # PENDING
    context 'when checking ready VMs' do
      let(:pool_check_response) {
        {
          discovered_vms: 0,
          checked_running_vms: 0,
          checked_ready_vms: 0,
          checked_pending_vms: 0,
          destroyed_vms: 0,
          migrated_vms: 0,
          cloned_vms: 0
        }
      }

      it 'should call #check_ready_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_pending_pool_vms).with(pool, provider, pool_check_response, {}, pool_object['timeout'])

        subject._check_pool(pool_object,provider)
      end
    end


    # COMPLETED
    context 'when checking completed VMs' do
      let(:pool_check_response) {
        {
            discovered_vms: 0,
            checked_running_vms: 0,
            checked_ready_vms: 0,
            checked_pending_vms: 0,
            destroyed_vms: 0,
            migrated_vms: 0,
            cloned_vms: 0
        }
      }

      it 'should call #check_completed_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_completed_pool_vms).with(pool, provider, pool_check_response, {})

        subject._check_pool(pool_object,provider)
      end
    end

    # DISCOVERED
    context 'when checking discovered VMs' do
      let(:pool_check_response) {
        {
            discovered_vms: 0,
            checked_running_vms: 0,
            checked_ready_vms: 0,
            checked_pending_vms: 0,
            destroyed_vms: 0,
            migrated_vms: 0,
            cloned_vms: 0
        }
      }

      it 'should call #check_discovered_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_discovered_pool_vms).with(pool)

        subject._check_pool(pool_object,provider)
      end
    end

    # MIGRATIONS
    context 'when checking migrating VMs' do
      let(:pool_check_response) {
        {
          discovered_vms: 0,
          checked_running_vms: 0,
          checked_ready_vms: 0,
          checked_pending_vms: 0,
          destroyed_vms: 0,
          migrated_vms: 0,
          cloned_vms: 0
        }
      }

      it 'should call #check_migrating_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:check_migrating_pool_vms).with(pool, provider, pool_check_response, {})

        subject._check_pool(pool_object,provider)
      end
    end

    # update_pool_size
    context 'when a pool size configuration change is detected' do
      let(:poolsize) { 2 }
      let(:newpoolsize) { 3 }
      before(:each) do
        config[:pools][0]['size'] = poolsize
        redis.hset('vmpooler__config__poolsize', pool, newpoolsize)
      end

      it 'should change the pool size configuration' do
        allow(subject).to receive(:create_inventory).and_return({})

        expect(subject).to receive(:update_pool_size).and_call_original

        subject._check_pool(config[:pools][0],provider)

        expect(config[:pools][0]['size']).to be(newpoolsize)
      end
    end

    #REPOPULATE
    context 'when checking if pools need to be repopulated' do
      let(:pool_check_response) { {
        discovered_vms: 0,
        checked_running_vms: 0,
        checked_ready_vms: 0,
        checked_pending_vms: 0,
        destroyed_vms: 0,
        migrated_vms: 0,
        cloned_vms: 0
      } }
      it 'should call #repopulate_pool_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:repopulate_pool_vms).with(pool, provider, pool_check_response, config[:pools][0]['size'])

        subject._check_pool(pool_object, provider)
      end
    end

    #remove_excess_vms
    context 'when an excess number of ready vms exist' do

      before(:each) do
        allow(redis).to receive(:scard)
        expect(redis).to receive(:scard).with("vmpooler__ready__#{pool}").and_return(1)
        expect(redis).to receive(:scard).with("vmpooler__pending__#{pool}").and_return(1)
      end

      it 'should call remove_excess_vms' do
        allow(subject).to receive(:create_inventory).and_return({})
        expect(subject).to receive(:remove_excess_vms).with(config[:pools][0])

        subject._check_pool(config[:pools][0],provider)
      end
    end

    #


  end
end
