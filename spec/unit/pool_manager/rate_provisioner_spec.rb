# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/pool_manager/rate_provisioner'

describe Vmpooler::PoolManager::RateProvisioner do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { MockRedis.new } }
  let(:rate_provisioner) { described_class.new(redis_connection_pool, logger, metrics) }

  describe '#enabled_for_pool?' do
    it 'returns false when rate_provisioning is not configured' do
      pool = { 'name' => 'test-pool', 'size' => 5 }
      expect(rate_provisioner.enabled_for_pool?(pool)).to be(false)
    end

    it 'returns false when rate_provisioning enabled is false' do
      pool = { 'name' => 'test-pool', 'size' => 5, 'rate_provisioning' => { 'enabled' => false } }
      expect(rate_provisioner.enabled_for_pool?(pool)).to be(false)
    end

    it 'returns true when rate_provisioning enabled is true' do
      pool = { 'name' => 'test-pool', 'size' => 5, 'rate_provisioning' => { 'enabled' => true } }
      expect(rate_provisioner.enabled_for_pool?(pool)).to be(true)
    end
  end

  describe '#get_ready_count' do
    let(:pool_name) { 'test-pool' }

    before do
      redis_connection_pool.with do |redis|
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm1')
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm2')
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm3')
      end
    end

    it 'returns correct ready count' do
      count = rate_provisioner.get_ready_count(pool_name)
      expect(count).to eq(3)
    end
  end

  describe '#get_clone_concurrency' do
    let(:pool_name) { 'test-pool' }
    let(:pool) do
      {
        'name' => pool_name,
        'rate_provisioning' => {
          'enabled' => true,
          'normal_concurrency' => 2,
          'high_demand_concurrency' => 5,
          'queue_depth_threshold' => 5
        }
      }
    end

    before do
      redis_connection_pool.with(&:flushdb)
    end

    it 'returns normal concurrency when demand is low' do
      redis_connection_pool.with do |redis|
        # 3 ready VMs, 0 pending requests
        (1..3).each { |i| redis.lpush("vmpooler__ready__#{pool_name}", "vm#{i}") }
      end

      allow(rate_provisioner).to receive(:get_pending_requests_count).and_return(0)

      concurrency = rate_provisioner.get_clone_concurrency(pool, pool_name)
      expect(concurrency).to eq(2)
    end

    it 'returns high demand concurrency when pending requests exceed threshold' do
      redis_connection_pool.with do |redis|
        # 2 ready VMs, 6 pending requests (exceeds threshold of 5)
        (1..2).each { |i| redis.lpush("vmpooler__ready__#{pool_name}", "vm#{i}") }
      end

      allow(rate_provisioner).to receive(:get_pending_requests_count).and_return(6)

      concurrency = rate_provisioner.get_clone_concurrency(pool, pool_name)
      expect(concurrency).to eq(5)
    end

    it 'returns high demand concurrency when no ready VMs and requests pending' do
      redis_connection_pool.with do |redis|
        # 0 ready VMs, 2 pending requests
      end

      allow(rate_provisioner).to receive(:get_pending_requests_count).and_return(2)

      concurrency = rate_provisioner.get_clone_concurrency(pool, pool_name)
      expect(concurrency).to eq(5)
    end

    it 'returns default concurrency when rate provisioning is disabled' do
      pool['rate_provisioning']['enabled'] = false
      pool['clone_target_concurrency'] = 3

      concurrency = rate_provisioner.get_clone_concurrency(pool, pool_name)
      expect(concurrency).to eq(3)
    end

    it 'returns default 2 when no configuration exists' do
      pool_without_config = { 'name' => pool_name }

      concurrency = rate_provisioner.get_clone_concurrency(pool_without_config, pool_name)
      expect(concurrency).to eq(2)
    end

    it 'logs mode changes' do
      redis_connection_pool.with do |redis|
        # Start in normal mode (3 ready VMs)
        (1..3).each { |i| redis.lpush("vmpooler__ready__#{pool_name}", "vm#{i}") }
      end

      allow(rate_provisioner).to receive(:get_pending_requests_count).and_return(0)

      # First call - normal mode
      rate_provisioner.get_clone_concurrency(pool, pool_name)

      # Change to high demand mode
      redis_connection_pool.with do |redis|
        redis.del("vmpooler__ready__#{pool_name}")
      end
      allow(rate_provisioner).to receive(:get_pending_requests_count).and_return(10)

      # Second call - should log mode change
      expect(logger).to receive(:log).with('s', /Provisioning mode: normal -> high_demand/)
      rate_provisioner.get_clone_concurrency(pool, pool_name)
    end
  end

  describe '#get_current_mode' do
    it 'returns normal mode by default' do
      expect(rate_provisioner.get_current_mode('test-pool')).to eq(:normal)
    end

    it 'returns current mode after it has been set' do
      rate_provisioner.instance_variable_get(:@current_mode)['test-pool'] = :high_demand
      expect(rate_provisioner.get_current_mode('test-pool')).to eq(:high_demand)
    end
  end

  describe '#reset_to_normal' do
    it 'resets mode to normal' do
      rate_provisioner.instance_variable_get(:@current_mode)['test-pool'] = :high_demand
      rate_provisioner.reset_to_normal('test-pool')
      expect(rate_provisioner.get_current_mode('test-pool')).to eq(:normal)
    end
  end
end
