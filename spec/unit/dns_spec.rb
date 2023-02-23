require 'spec_helper'

describe 'Vmpooler::Dns' do
  let(:dns_class) { 'mock-dnsservice' }
  let(:dns_config_name) { 'mock' }
  let(:pool) { 'pool1' }
  let(:config) { YAML.load(<<~EOT
  ---
  :dns_configs:
    :mock:
      dns_class: 'mock'
      domain: 'example.com'
  :pools:
    - name: 'pool1'
      dns_plugin: 'mock'
EOT
  )}
  subject { Vmpooler::Dns.new }

  describe '.get_dns_plugin_class_by_name' do
    it 'returns the plugin class for the specified config' do
      result = Vmpooler::Dns.get_dns_plugin_class_by_name(config, dns_config_name)
      expect(result).to eq('mock')
    end
  end

  describe '.get_domain_for_pool' do
    it 'returns the domain for the specified pool' do
      result = Vmpooler::Dns.get_domain_for_pool(config, pool)
      expect(result).to eq('example.com')
    end
  end

  describe '.get_dns_plugin_domain_by_name' do
    it 'returns the domain for the specified config' do
      result = Vmpooler::Dns.get_dns_plugin_domain_by_name(config, dns_config_name)
      expect(result).to eq('example.com')
    end
  end

  describe '.get_dns_plugin_config_classes' do
    it 'returns the list of dns plugin classes' do
      result = Vmpooler::Dns.get_dns_plugin_config_classes(config)
      expect(result).to eq(['mock'])
    end
  end

  describe '#load_from_gems' do
    let(:gem_name) { 'mock-dnsservice' }
    let(:translated_gem_name) { 'mock/dnsservice' }

    before(:each) do
      allow(subject).to receive(:require).with(gem_name).and_return(true)
    end

    it 'loads the specified gem' do
      expect(subject).to receive(:require).with("vmpooler/dns/#{translated_gem_name}")
      result = subject.load_from_gems(gem_name)
      expect(result).to eq("vmpooler/dns/#{translated_gem_name}")
    end
  end
end
