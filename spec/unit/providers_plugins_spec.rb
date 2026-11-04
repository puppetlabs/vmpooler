# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/providers'
require 'vmpooler/providers/dummy'

describe Vmpooler::Providers do
  # Providers#plugin_classes calls load_plugins, which is not defined anywhere,
  # so it raises NameError unless a subclass supplies it. Supply it here.
  let(:providers) do
    described_class.new.tap { |p| p.define_singleton_method(:load_plugins) { @load_count = (@load_count || 0) + 1 } }
  end

  it 'raises NameError from plugin_classes when load_plugins is not defined (existing bug)' do
    expect { described_class.new.send(:plugin_classes) }.to raise_error(NameError, /load_plugins/)
  end

  # plugin_classes keeps classes whose name has exactly 3 segments, so a real
  # provider such as Vmpooler::PoolManager::Provider::Dummy (4) is never found.
  let(:fake) { stub_const('Vmpooler::PoolManager::ProviderFake', Class.new) }

  describe '#plugin_classes' do
    it 'finds the provider classes that are loaded' do
      fake
      expect(providers.send(:plugin_classes)).to include(fake)
    end

    it 'only looks once' do
      first = providers.send(:plugin_classes)

      expect(providers.send(:plugin_classes)).to be(first)
      expect(providers.instance_variable_get(:@load_count)).to eq(1)
    end

    it 'leaves out the excluded classes' do
      fake
      allow(providers).to receive(:excluded_classes).and_return([fake])

      expect(providers.send(:plugin_classes)).not_to include(fake)
    end
  end

  describe '#plugin_map' do
    it 'maps class names to classes' do
      fake
      # ObjectSpace can still hold a stubbed class from an earlier example, so compare by name
      expect(providers.send(:plugin_map)['Vmpooler::PoolManager::ProviderFake'].name).to eq(fake.name)
    end

    it 'is built once' do
      map = providers.send(:plugin_map)

      expect(providers.send(:plugin_map)).to be(map)
    end
  end
end
