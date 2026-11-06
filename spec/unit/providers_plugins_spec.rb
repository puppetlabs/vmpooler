# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/providers'
require 'vmpooler/providers/dummy'

describe Vmpooler::Providers do
  let(:providers) { described_class.new }
  let(:dummy) { Vmpooler::PoolManager::Provider::Dummy }

  describe '#plugin_classes' do
    it 'finds the provider classes that are loaded' do
      expect(providers.send(:plugin_classes)).to include(dummy)
    end

    it 'loads the provider files first, and only once' do
      expect(providers).to receive(:load_from_gems).once

      first = providers.send(:plugin_classes)

      expect(providers.send(:plugin_classes)).to be(first)
    end

    it 'leaves out the excluded classes' do
      allow(providers).to receive(:excluded_classes).and_return([dummy])

      expect(providers.send(:plugin_classes)).not_to include(dummy)
    end
  end

  describe '#plugin_map' do
    it 'maps class names to classes' do
      expect(providers.send(:plugin_map)['Vmpooler::PoolManager::Provider::Dummy']).to be(dummy)
    end

    it 'is built once' do
      map = providers.send(:plugin_map)

      expect(providers.send(:plugin_map)).to be(map)
    end
  end
end
