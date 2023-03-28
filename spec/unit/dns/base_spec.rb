require 'spec_helper'
require 'vmpooler/dns/base'

# This spec does not really exercise code paths but is merely used
# to enforce that certain methods are defined in the base classes

describe 'Vmpooler::PoolManager::Dns::Base' do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:config) { {} }
  let(:dns_plugin_name) { 'base' }
  let(:dns_options) { { 'param' => 'value' } }

  let(:fake_vm) {
    fake_vm = {}
    fake_vm['name'] = 'vm1'
    fake_vm['hostname'] = 'vm1'
    fake_vm['template'] = 'pool1'
    fake_vm['boottime'] = Time.now
    fake_vm['powerstate'] = 'PoweredOn'

    fake_vm
  }

  let(:redis_connection_pool) { Vmpooler::PoolManager::GenericConnectionPool.new(
    metrics: metrics,
    connpool_type: 'redis_connection_pool',
    connpool_provider: 'testprovider',
    size: 1,
    timeout: 5
  ) { MockRedis.new }
  }

  subject { Vmpooler::PoolManager::Dns::Base.new(config, logger, metrics, redis_connection_pool, dns_plugin_name, dns_options) }

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

  describe '#dns_options' do
    it 'should come from the provider initialization' do
      expect(subject.dns_options).to be(dns_options)
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

  describe '#dns_config' do
    let(:poolname) { 'pool1' }
    let(:config) { YAML.load(<<-EOT
---
:dns_configs:
  :#{dns_plugin_name}:
    option1: 'value1'
EOT
      )
    }

    context 'Given a dns plugin with no configuration' do
    let(:config) { YAML.load(<<-EOT
---
:dns_configs:
  :bad_dns:
    option1: 'value1'
    option2: 'value1'
EOT
      )
    }
      it 'should return nil' do
        expect(subject.dns_config).to be_nil
      end
    end

    context 'Given a correct dns config name' do
      it 'should return the dns\'s configuration' do
        result = subject.dns_config
        expect(result['option1']).to eq('value1')
      end
    end
  end

  describe '#global_config' do
    it 'should come from the dns initialization' do
      expect(subject.global_config).to be(config)
    end
  end

  describe '#name' do
    it "should come from the dns initialization" do
      expect(subject.name).to eq(dns_plugin_name)
    end
  end

  describe '#get_ip' do
    it 'calls redis hget with vm name and ip' do
      redis_connection_pool.with do |redis|
        expect(redis).to receive(:hget).with("vmpooler__vm__vm1", 'ip')
      end
      subject.get_ip(fake_vm['name'])
    end
  end

  describe '#provided_pools' do
    let(:config) { YAML.load(<<-EOT
---
:pools:
  - name: 'pool1'
    dns_config: 'base'
  - name: 'pool2'
    dns_config: 'base'
  - name: 'otherpool'
    dns_config: 'other provider'
  - name: 'no name'
EOT
      )
    }

    it "should return pools serviced by this provider" do
      expect(subject.provided_pools).to eq(['pool1','pool2'])
    end
  end

  describe '#create_or_replace_record' do
    it 'should raise error' do
      expect{subject.create_or_replace_record('pool')}.to raise_error(/does not implement create_or_replace_record/)
    end
  end

  describe '#delete_record' do
    it 'should raise error' do
      expect{subject.delete_record('pool')}.to raise_error(/does not implement delete_record/)
    end
  end
end
