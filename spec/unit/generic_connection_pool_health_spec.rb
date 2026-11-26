# frozen_string_literal: true

require 'spec_helper'

describe Vmpooler::PoolManager::GenericConnectionPool do
  let(:pool) { described_class.new(size: 10, timeout: 1) { Object.new } }
  let(:available) { pool.instance_variable_get(:@available) }

  def use(connections)
    allow(available).to receive(:length).and_return(10 - connections)
  end

  def waiting(threads)
    pool.instance_variable_set(:@queue, double('queue', length: threads))
  end

  describe '#health_status' do
    it 'reports the size, what is free and in use, and how busy the pool is' do
      use(4)

      expect(pool.health_status).to eq(
        size: 10, available: 6, in_use: 4, utilization: 40.0, waiting_threads: 0, state: :healthy
      )
    end

    it 'reports threads waiting for a connection' do
      use(0)
      waiting(2)

      expect(pool.health_status[:waiting_threads]).to eq(2)
    end

    it 'rounds the utilization to two decimals' do
      three = described_class.new(size: 3, timeout: 1) { Object.new }
      allow(three.instance_variable_get(:@available)).to receive(:length).and_return(2)

      expect(three.health_status[:utilization]).to eq(33.33)
    end
  end

  describe 'the health state' do
    it 'is healthy while the pool is under 70% used and few threads wait' do
      use(6)
      waiting(2)

      expect(pool.health_status[:state]).to eq(:healthy)
    end

    it 'is a warning from 70% used' do
      use(7)

      expect(pool.health_status[:state]).to eq(:warning)
    end

    it 'is a warning when more than 2 threads wait' do
      use(0)
      waiting(3)

      expect(pool.health_status[:state]).to eq(:warning)
    end

    it 'is critical from 90% used' do
      use(9)

      expect(pool.health_status[:state]).to eq(:critical)
    end

    it 'is critical when more than 5 threads wait' do
      use(0)
      waiting(6)

      expect(pool.health_status[:state]).to eq(:critical)
    end
  end
end
