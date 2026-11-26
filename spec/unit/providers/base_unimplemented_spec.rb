# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/providers/base'

describe 'Vmpooler::PoolManager::Provider::Base methods a provider must supply' do
  let(:logger) { double('logger', log: nil) }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:config) { { dns_configs: {} } }
  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { MockRedis.new } }
  let(:provider) { Vmpooler::PoolManager::Provider::Base.new(config, logger, metrics, redis_connection_pool, 'base', {}) }
  let(:name) { 'Vmpooler::PoolManager::Provider::Base' }

  it 'refuses to migrate a VM' do
    expect { provider.migrate_vm('pool1', 'vm1', nil) }.to raise_error(RuntimeError, "#{name} does not implement migrate_vm")
  end

  it 'refuses to find the target datacenter' do
    expect { provider.get_target_datacenter_from_config('base') }
      .to raise_error(RuntimeError, "#{name} does not implement get_target_datacenter_from_config")
  end

  it 'refuses to purge unconfigured resources' do
    expect { provider.purge_unconfigured_resources([]) }
      .to raise_error(RuntimeError, "#{name} does not implement purge_unconfigured_resources")
  end

  it 'refuses to give the IP address of a VM' do
    expect { provider.get_vm_ip_address('vm1', 'pool1') }
      .to raise_error(RuntimeError, "#{name} does not implement get_vm_ip_address for vm vm1 in pool pool1")
  end

  it 'only says it does not create template delta disks' do
    expect { provider.create_template_delta_disks('pool1') }
      .to output("#{name} does not implement create_template_delta_disks\n").to_stdout
  end

  it 'passes the deprecated purge_unconfigured_folders on to purge_unconfigured_resources, and says so' do
    expect(provider).to receive(:purge_unconfigured_resources).with(['allowed'])

    provider.purge_unconfigured_folders(nil, nil, ['allowed'])

    expect(logger).to have_received(:log).with('s', /purge_unconfigured_folders was renamed to purge_unconfigured_resources/)
  end

  it 'looks up a DNS config by name' do
    expect(Vmpooler::Dns).to receive(:get_dns_plugin_domain_by_name).with(config, 'example').and_return('example.com')

    expect(provider.dns_config('example')).to eq('example.com')
  end
end
