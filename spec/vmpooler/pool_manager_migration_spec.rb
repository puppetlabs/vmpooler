require 'spec_helper'
require 'mock_redis'
require 'time'

describe 'Pool Manager' do
  let(:logger) { double('logger') }
  let(:redis) { MockRedis.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) {
    {
      config: {
        'site_name' => 'test pooler',
        'migration_limit' => 2,
        vsphere: {
          'server' => 'vsphere.puppet.com',
          'username' => 'vmpooler@vsphere.local',
          'password' => '',
          'insecure' => true
        },
        pools: [ {'name' => 'pool1', 'size' => 5, 'folder' => 'pool1_folder'} ],
        statsd: { 'prefix' => 'stats_prefix'},
        pool_names: [ 'pool1' ]
      }
    }
  }
  let(:pool) { config[:config][:pools][0]['name'] }
  let(:vm) {
    {
      'name' => 'vm1',
      'host' => 'host1',
      'template' => pool,
    }
  }

  describe '#_migrate_vm' do
    let(:vsphere) { double(pool) }
    let(:pooler) { Vmpooler::PoolManager.new(config, logger, redis, metrics) }
    context 'evaluates VM for migration and logs host' do
      before do
        create_migrating_vm vm['name'], pool, redis
        allow(vsphere).to receive(:find_vm).and_return(vm)
        allow(pooler).to receive(:get_vm_host_info).and_return([{'name' => 'host1'}, 'host1'])
      end

      it 'logs VM host when migration is disabled' do
        config[:config]['migration_limit'] = nil

        expect(redis.sismember("vmpooler__migrating__#{pool}", vm['name'])).to be true
        expect(logger).to receive(:log).with('s', "[ ] [#{pool}] '#{vm['name']}' is running on #{vm['host']}")

        pooler._migrate_vm(vm['name'], pool, vsphere)

        expect(redis.sismember("vmpooler__migrating__#{pool}", vm['name'])).to be false
      end

      it 'verifies that migration_limit greater than or equal to migrations in progress and logs host' do
        add_vm_to_migration_set vm['name'], redis
        add_vm_to_migration_set 'vm2', redis

        expect(logger).to receive(:log).with('s', "[ ] [#{pool}] '#{vm['name']}' is running on #{vm['host']}. No migration will be evaluated since the migration_limit has been reached")

        pooler._migrate_vm(vm['name'], pool, vsphere)
      end

      it 'verifies that migration_limit is less than migrations in progress and logs old host, new host and migration time' do
        allow(vsphere).to receive(:find_least_used_compatible_host).and_return([{'name' => 'host2'}, 'host2'])
        allow(vsphere).to receive(:migrate_vm_host)

        expect(redis.hget("vmpooler__vm__#{vm['name']}", 'migration_time'))
        expect(redis.hget("vmpooler__vm__#{vm['name']}", 'checkout_to_migration'))
        expect(logger).to receive(:log).with('s', "[>] [#{pool}] '#{vm['name']}' migrated from #{vm['host']} to host2 in 0.00 seconds")

        pooler._migrate_vm(vm['name'], pool, vsphere)
      end

      it 'fails when no suitable host can be found' do
        error = 'ArgumentError: No target host found'
        allow(vsphere).to receive(:find_least_used_compatible_host)
        allow(vsphere).to receive(:migrate_vm_host).and_raise(error)

        expect(logger).to receive(:log).with('s', "[x] [#{pool}] '#{vm['name']}' migration failed with an error: #{error}")

        pooler._migrate_vm(vm['name'], pool, vsphere)
      end
    end
  end
end
