require 'spec_helper'
require 'vmpooler/providers/base'

# This spec does not really exercise code paths but is merely used
# to enforce that certain methods are defined in the base classes

describe 'Vmpooler::PoolManager::Provider::Base' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) { {} }
  let(:provider_name) { 'base' }
  let(:provider_options) { { 'param' => 'value' } }

  let(:fake_vm) {
    fake_vm = {}
    fake_vm['name'] = 'vm1'
    fake_vm['hostname'] = 'vm1'
    fake_vm['template'] = 'pool1'
    fake_vm['boottime'] = Time.now
    fake_vm['powerstate'] = 'PoweredOn'

    fake_vm
  }

  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { MockRedis.new } }

  subject { Vmpooler::PoolManager::Provider::Base.new(config, logger, metrics, redis_connection_pool, provider_name, provider_options) }

  # Helper attr_reader methods
  describe '#logger' do
    it 'should come from the provider initialization' do
      expect(subject.logger).to be(logger)
    end
  end

  describe '#metrics' do
    it 'should come from the provider initialization' do
      expect(subject.metrics).to be(metrics)
    end
  end

  describe '#provider_options' do
    it 'should come from the provider initialization' do
      expect(subject.provider_options).to be(provider_options)
    end
  end

  describe '#pool_config' do
    let(:poolname) { 'pool1' }
    let(:config) { YAML.load(<<-EOT
---
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
    context 'Given a pool that does not exist' do
      it 'should return nil' do
        expect(subject.pool_config('missing_pool')).to be_nil
      end
    end

    context 'Given a pool that does exist' do
      it 'should return the pool\'s configuration' do
        result = subject.pool_config(poolname)
        expect(result['name']).to eq(poolname)
      end
    end
  end

  describe '#provider_config' do
    let(:poolname) { 'pool1' }
    let(:config) { YAML.load(<<-EOT
---
:providers:
  :#{provider_name}:
    option1: 'value1'
EOT
      )
    }

    context 'Given a provider with no configuration' do
    let(:config) { YAML.load(<<-EOT
---
:providers:
  :bad_provider:
    option1: 'value1'
    option2: 'value1'
EOT
      )
    }
      it 'should return empty hash' do
        expect(subject.provider_config).to eq({})
      end
    end

    context 'Given a correct provider name' do
      it 'should return the provider\'s configuration' do
        result = subject.provider_config
        expect(result['option1']).to eq('value1')
      end
    end
  end

  describe '#global_config' do
    it 'should come from the provider initialization' do
      expect(subject.global_config).to be(config)
    end
  end

  # Pool Manager Methods
  describe '#name' do
    it "should come from the provider initialization" do
      expect(subject.name).to eq(provider_name)
    end
  end

  describe '#provided_pools' do
    let(:config) { YAML.load(<<-EOT
---
:pools:
  - name: 'pool1'
    provider: 'base'
  - name: 'pool2'
    provider: 'base'
  - name: 'otherpool'
    provider: 'other provider'
  - name: 'no name'
EOT
      )
    }

    it "should return pools serviced by this provider" do
      expect(subject.provided_pools).to eq(['pool1','pool2'])
    end
  end

  describe '#vms_in_pool' do
    it 'should raise error' do
      expect{subject.vms_in_pool('pool')}.to raise_error(/does not implement vms_in_pool/)
    end
  end

  describe '#get_vm_host' do
    it 'should raise error' do
      expect{subject.get_vm_host('pool', 'vm')}.to raise_error(/does not implement get_vm_host/)
    end
  end

  describe '#find_least_used_compatible_host' do
    it 'should raise error' do
      expect{subject.find_least_used_compatible_host('pool', 'vm')}.to raise_error(/does not implement find_least_used_compatible_host/)
    end
  end

  describe '#migrate_vm_to_host' do
    it 'should raise error' do
      expect{subject.migrate_vm_to_host('pool', 'vm','host')}.to raise_error(/does not implement migrate_vm_to_host/)
    end
  end

  describe '#get_vm' do
    it 'should raise error' do
      expect{subject.get_vm('pool', 'vm')}.to raise_error(/does not implement get_vm/)
    end
  end

  describe '#create_vm' do
    it 'should raise error' do
      expect{subject.create_vm('pool','newname')}.to raise_error(/does not implement create_vm/)
    end
  end

  describe '#create_disk' do
    it 'should raise error' do
      expect{subject.create_disk('pool', 'vm', 10)}.to raise_error(/does not implement create_disk/)
    end
  end

  describe '#create_snapshot' do
    it 'should raise error' do
      expect{subject.create_snapshot('pool', 'vm', 'snapshot')}.to raise_error(/does not implement create_snapshot/)
    end
  end

  describe '#revert_snapshot' do
    it 'should raise error' do
      expect{subject.revert_snapshot('pool', 'vm', 'snapshot')}.to raise_error(/does not implement revert_snapshot/)
    end
  end

  describe '#destroy_vm' do
    it 'should raise error' do
      expect{subject.destroy_vm('pool', 'vm')}.to raise_error(/does not implement destroy_vm/)
    end
  end

  describe '#vm_ready?' do
    it 'should raise error' do
      expect{subject.vm_ready?('pool', 'vm')}.to raise_error(/does not implement vm_ready?/)
    end
  end

  describe '#vm_exists?' do
    it 'should raise error' do
      expect{subject.vm_exists?('pool', 'vm')}.to raise_error(/does not implement/)
    end

    it 'should return true when get_vm returns an object' do
      allow(subject).to receive(:get_vm).with('pool', 'vm').and_return(fake_vm)

      expect(subject.vm_exists?('pool', 'vm')).to eq(true)
    end

    it 'should return false when get_vm returns nil' do
      allow(subject).to receive(:get_vm).with('pool', 'vm').and_return(nil)

      expect(subject.vm_exists?('pool', 'vm')).to eq(false)
    end
  end
end
