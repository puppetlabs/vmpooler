require 'spec_helper'
require 'mock_redis'
require 'time'

describe 'Pool Manager' do
  let(:redis) { MockRedis.new }
  let(:logger) { double('logger') }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) {
    {
      config: {
        'migration_limit' => 2,
      }
    }
  }
  let(:backingservice) { double('backingservice') }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) {
    fake_vm = {}
    fake_vm['name'] = 'vm1'
    fake_vm['hostname'] = 'vm1'
    fake_vm['template'] = 'pool1'
    fake_vm['boottime'] = Time.now
    fake_vm['powerstate'] = 'PoweredOn'

    fake_vm
  }
  let(:vm_host_hostname) { 'host1' }

  subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

  describe "#migration_limit" do
    it 'return false if config is nil' do
      expect(subject.migration_limit(nil)).to equal(false)
    end
    it 'return false if config is 0' do
      expect(subject.migration_limit(0)).to equal(false)
    end
    it 'return nil if config is -1' do
      expect(subject.migration_limit(-1)).to equal(nil)
    end
    it 'return 1 if config is 1' do
      expect(subject.migration_limit(1)).to equal(1)
    end
    it 'return 100 if config is 100' do
      expect(subject.migration_limit(100)).to equal(100)
    end
  end

  describe '#_migrate_vm' do
    context 'evaluates VM for migration and logs host' do
      before do
        create_migrating_vm vm, pool, redis
        allow(backingservice).to receive(:get_vm_host).with(vm).and_return(vm_host_hostname)
      end

      it 'logs VM host when migration is disabled' do
        config[:config]['migration_limit'] = nil

        expect(redis.sismember("vmpooler__migrating__#{pool}", vm)).to be true
        expect(logger).to receive(:log).with('s', "[ ] [#{pool}] '#{vm}' is running on #{vm_host_hostname}")

        subject._migrate_vm(vm, pool, backingservice)

        expect(redis.sismember("vmpooler__migrating__#{pool}", vm)).to be false
      end

      it 'verifies that migration_limit greater than or equal to migrations in progress and logs host' do
        add_vm_to_migration_set vm, redis
        add_vm_to_migration_set 'vm2', redis

        expect(logger).to receive(:log).with('s', "[ ] [#{pool}] '#{vm}' is running on #{vm_host_hostname}. No migration will be evaluated since the migration_limit has been reached")

        subject._migrate_vm(vm, pool, backingservice)
      end

      it 'verifies that migration_limit is less than migrations in progress and logs old host, new host and migration time' do
        allow(backingservice).to receive(:find_least_used_compatible_host).and_return('host2')
        allow(backingservice).to receive(:migrate_vm_to_host).and_return(true)

        expect(redis.hget("vmpooler__vm__#{vm['name']}", 'migration_time'))
        expect(redis.hget("vmpooler__vm__#{vm['name']}", 'checkout_to_migration'))
        expect(logger).to receive(:log).with('s', "[>] [#{pool}] '#{vm}' migrated from #{vm_host_hostname} to host2 in 0.00 seconds")

        subject._migrate_vm(vm, pool, backingservice)
      end

      it 'fails when no suitable host can be found' do
        error = 'ArgumentError: No target host found'
        allow(backingservice).to receive(:find_least_used_compatible_host).and_return('host2')
        allow(backingservice).to receive(:migrate_vm_to_host).and_raise(error)

        expect{subject._migrate_vm(vm, pool, backingservice)}.to raise_error(error)
      end
    end
  end
end
