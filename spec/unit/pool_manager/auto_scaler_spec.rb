# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/pool_manager/auto_scaler'

describe Vmpooler::PoolManager::AutoScaler do
  let(:logger) { MockLogger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { MockRedis.new } }
  let(:auto_scaler) { described_class.new(redis_connection_pool, logger, metrics) }

  describe '#enabled_for_pool?' do
    it 'returns false when auto_scale is not configured' do
      pool = { 'name' => 'test-pool', 'size' => 5 }
      expect(auto_scaler.enabled_for_pool?(pool)).to be(false)
    end

    it 'returns false when auto_scale enabled is false' do
      pool = { 'name' => 'test-pool', 'size' => 5, 'auto_scale' => { 'enabled' => false } }
      expect(auto_scaler.enabled_for_pool?(pool)).to be(false)
    end

    it 'returns true when auto_scale enabled is true' do
      pool = { 'name' => 'test-pool', 'size' => 5, 'auto_scale' => { 'enabled' => true } }
      expect(auto_scaler.enabled_for_pool?(pool)).to be(true)
    end
  end

  describe '#get_pool_metrics' do
    let(:pool_name) { 'test-pool' }

    before do
      redis_connection_pool.with do |redis|
        # Set up mock Redis data
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm1')
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm2')
        redis.sadd("vmpooler__running__#{pool_name}", 'vm3')
        redis.sadd("vmpooler__running__#{pool_name}", 'vm4')
        redis.sadd("vmpooler__running__#{pool_name}", 'vm5')
        redis.lpush("vmpooler__pending__#{pool_name}", 'vm6')
      end
    end

    it 'returns correct metrics' do
      metrics = auto_scaler.get_pool_metrics(pool_name)
      expect(metrics[:ready]).to eq(2)
      expect(metrics[:running]).to eq(3)
      expect(metrics[:pending]).to eq(1)
    end
  end

  describe '#calculate_scale_up_size' do
    it 'doubles size when ready percentage is very low' do
      new_size = auto_scaler.calculate_scale_up_size(10, 50, 5, 20)
      expect(new_size).to eq(20) # Doubled
    end

    it 'increases by 50% when ready percentage is moderately low' do
      new_size = auto_scaler.calculate_scale_up_size(10, 50, 15, 20)
      expect(new_size).to eq(15) # 1.5x = 15
    end

    it 'respects max_size limit' do
      new_size = auto_scaler.calculate_scale_up_size(10, 15, 5, 20)
      expect(new_size).to eq(15) # Would be 20, but max is 15
    end
  end

  describe '#calculate_scale_down_size' do
    it 'reduces by 25%' do
      new_size = auto_scaler.calculate_scale_down_size(20, 5, 85, 80)
      expect(new_size).to eq(15) # 20 * 0.75 = 15
    end

    it 'respects min_size limit' do
      new_size = auto_scaler.calculate_scale_down_size(10, 8, 85, 80)
      expect(new_size).to eq(8) # Would be 7.5 (floor to 7), but min is 8
    end
  end

  describe '#calculate_target_size' do
    let(:pool_name) { 'test-pool' }
    let(:pool) do
      {
        'name' => pool_name,
        'size' => 10,
        'auto_scale' => {
          'enabled' => true,
          'min_size' => 5,
          'max_size' => 20,
          'scale_up_threshold' => 20,
          'scale_down_threshold' => 80,
          'cooldown_period' => 300
        }
      }
    end

    before do
      redis_connection_pool.with do |redis|
        # Clear any existing data
        redis.flushdb
      end
    end

    it 'scales up when ready percentage is low' do
      redis_connection_pool.with do |redis|
        # 1 ready, 9 running = 10% ready
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm1')
        (2..10).each { |i| redis.sadd("vmpooler__running__#{pool_name}", "vm#{i}") }
      end

      new_size = auto_scaler.calculate_target_size(pool, pool_name)
      expect(new_size).to be > 10
    end

    it 'scales down when ready percentage is high and no pending requests' do
      redis_connection_pool.with do |redis|
        # 9 ready, 1 running = 90% ready
        (1..9).each { |i| redis.lpush("vmpooler__ready__#{pool_name}", "vm#{i}") }
        redis.sadd("vmpooler__running__#{pool_name}", 'vm10')
      end

      # Mock no pending requests
      allow(auto_scaler).to receive(:get_pending_requests_count).and_return(0)

      new_size = auto_scaler.calculate_target_size(pool, pool_name)
      expect(new_size).to be < 10
    end

    it 'does not scale during cooldown period' do
      # Set last scale time to now
      auto_scaler.instance_variable_get(:@last_scale_time)[pool_name] = Time.now

      redis_connection_pool.with do |redis|
        # 1 ready, 9 running = should trigger scale up
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm1')
        (2..10).each { |i| redis.sadd("vmpooler__running__#{pool_name}", "vm#{i}") }
      end

      new_size = auto_scaler.calculate_target_size(pool, pool_name)
      expect(new_size).to eq(10) # No change due to cooldown
    end

    it 'does not scale down if there are pending requests' do
      redis_connection_pool.with do |redis|
        # 9 ready, 1 running = should trigger scale down
        (1..9).each { |i| redis.lpush("vmpooler__ready__#{pool_name}", "vm#{i}") }
        redis.sadd("vmpooler__running__#{pool_name}", 'vm10')
      end

      # Mock pending requests
      allow(auto_scaler).to receive(:get_pending_requests_count).and_return(5)

      new_size = auto_scaler.calculate_target_size(pool, pool_name)
      expect(new_size).to eq(10) # No scale down due to pending requests
    end
  end

  describe '#update_pool_size_in_redis' do
    let(:pool_name) { 'test-pool' }

    it 'updates pool size in Redis' do
      auto_scaler.update_pool_size_in_redis(pool_name, 15)

      redis_connection_pool.with do |redis|
        size = redis.hget("vmpooler__pool__#{pool_name}", 'size')
        expect(size).to eq('15')
      end
    end
  end

  describe '#apply_auto_scaling' do
    let(:pool_name) { 'test-pool' }
    let(:pool) do
      {
        'name' => pool_name,
        'size' => 10,
        'auto_scale' => {
          'enabled' => true,
          'min_size' => 5,
          'max_size' => 20,
          'scale_up_threshold' => 20,
          'scale_down_threshold' => 80
        }
      }
    end

    before do
      redis_connection_pool.with do |redis|
        redis.flushdb
        # 1 ready, 9 running = 10% ready (should scale up)
        redis.lpush("vmpooler__ready__#{pool_name}", 'vm1')
        (2..10).each { |i| redis.sadd("vmpooler__running__#{pool_name}", "vm#{i}") }
      end
    end

    it 'applies auto-scaling to pool' do
      auto_scaler.apply_auto_scaling(pool)

      # Pool size should have increased
      expect(pool['size']).to be > 10

      # Redis should be updated
      redis_connection_pool.with do |redis|
        size = redis.hget("vmpooler__pool__#{pool_name}", 'size').to_i
        expect(size).to eq(pool['size'])
      end
    end

    it 'does nothing if auto-scaling is disabled' do
      pool['auto_scale']['enabled'] = false
      original_size = pool['size']

      auto_scaler.apply_auto_scaling(pool)

      expect(pool['size']).to eq(original_size)
    end

    it 'handles errors gracefully' do
      allow(auto_scaler).to receive(:calculate_target_size).and_raise(StandardError.new('Test error'))

      expect { auto_scaler.apply_auto_scaling(pool) }.not_to raise_error
    end
  end
end
