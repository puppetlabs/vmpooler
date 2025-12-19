# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/pool_manager'

describe 'Vmpooler::PoolManager - Queue Reliability Features' do
  let(:logger) { MockLogger.new }
  let(:redis_connection_pool) { ConnectionPool.new(size: 1) { redis } }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:config) { YAML.load(<<~EOT
    ---
    :config:
      task_limit: 10
      vm_checktime: 1
      vm_lifetime: 12
      prefix: 'pooler-'
      dlq_enabled: true
      dlq_ttl: 168
      dlq_max_entries: 100
      purge_enabled: true
      purge_dry_run: false
      max_pending_age: 7200
      max_ready_age: 86400
      max_completed_age: 3600
      health_check_enabled: true
      health_check_interval: 300
      health_thresholds:
        pending_queue_max: 100
        ready_queue_max: 500
        dlq_max_warning: 100
        dlq_max_critical: 1000
        stuck_vm_age_threshold: 7200
    :providers:
      :dummy: {}
    :pools:
      - name: 'test-pool'
        size: 5
        provider: 'dummy'
    EOT
    )
  }

  subject { Vmpooler::PoolManager.new(config, logger, redis_connection_pool, metrics) }

  describe 'Dead-Letter Queue (DLQ)' do
    let(:vm) { 'vm-abc123' }
    let(:pool) { 'test-pool' }
    let(:error_class) { 'StandardError' }
    let(:error_message) { 'template does not exist' }
    let(:request_id) { 'req-123' }
    let(:pool_alias) { 'test-alias' }

    before(:each) do
      redis_connection_pool.with do |redis_connection|
        allow(redis_connection).to receive(:zadd)
        allow(redis_connection).to receive(:zcard).and_return(0)
        allow(redis_connection).to receive(:expire)
      end
    end

    describe '#dlq_enabled?' do
      it 'returns true when dlq_enabled is true in config' do
        expect(subject.dlq_enabled?).to be true
      end

      it 'returns false when dlq_enabled is false in config' do
        config[:config]['dlq_enabled'] = false
        expect(subject.dlq_enabled?).to be false
      end
    end

    describe '#dlq_ttl' do
      it 'returns configured TTL' do
        expect(subject.dlq_ttl).to eq(168)
      end

      it 'returns default TTL when not configured' do
        config[:config].delete('dlq_ttl')
        expect(subject.dlq_ttl).to eq(168)
      end
    end

    describe '#dlq_max_entries' do
      it 'returns configured max entries' do
        expect(subject.dlq_max_entries).to eq(100)
      end

      it 'returns default max entries when not configured' do
        config[:config].delete('dlq_max_entries')
        expect(subject.dlq_max_entries).to eq(10000)
      end
    end

    describe '#move_to_dlq' do
      context 'when DLQ is enabled' do
        it 'adds entry to DLQ sorted set' do
          redis_connection_pool.with do |redis_connection|
            dlq_key = 'vmpooler__dlq__pending'
            
            expect(redis_connection).to receive(:zadd).with(dlq_key, anything, anything)
            expect(redis_connection).to receive(:expire).with(dlq_key, anything)
            
            subject.move_to_dlq(vm, pool, 'pending', error_class, error_message, 
                               redis_connection, request_id: request_id, pool_alias: pool_alias)
          end
        end

        it 'includes error details in DLQ entry' do
          redis_connection_pool.with do |redis_connection|
            expect(redis_connection).to receive(:zadd) do |_key, _score, entry|
              expect(entry).to include(vm)
              expect(entry).to include(error_message)
              expect(entry).to include(error_class)
            end
            
            subject.move_to_dlq(vm, pool, 'pending', error_class, error_message, redis_connection)
          end
        end

        it 'increments DLQ metrics' do
          redis_connection_pool.with do |redis_connection|
            expect(metrics).to receive(:increment).with('dlq.pending.count')
            
            subject.move_to_dlq(vm, pool, 'pending', error_class, error_message, redis_connection)
          end
        end

        it 'enforces max entries limit' do
          redis_connection_pool.with do |redis_connection|
            allow(redis_connection).to receive(:zcard).and_return(150)
            expect(redis_connection).to receive(:zremrangebyrank).with(anything, 0, 49)
            
            subject.move_to_dlq(vm, pool, 'pending', error_class, error_message, redis_connection)
          end
        end
      end

      context 'when DLQ is disabled' do
        before { config[:config]['dlq_enabled'] = false }

        it 'does not add entry to DLQ' do
          redis_connection_pool.with do |redis_connection|
            expect(redis_connection).not_to receive(:zadd)
            
            subject.move_to_dlq(vm, pool, 'pending', error_class, error_message, redis_connection)
          end
        end
      end
    end
  end

  describe 'Auto-Purge' do
    describe '#purge_enabled?' do
      it 'returns true when purge_enabled is true in config' do
        expect(subject.purge_enabled?).to be true
      end

      it 'returns false when purge_enabled is false in config' do
        config[:config]['purge_enabled'] = false
        expect(subject.purge_enabled?).to be false
      end
    end

    describe '#purge_dry_run?' do
      it 'returns false when purge_dry_run is false in config' do
        expect(subject.purge_dry_run?).to be false
      end

      it 'returns true when purge_dry_run is true in config' do
        config[:config]['purge_dry_run'] = true
        expect(subject.purge_dry_run?).to be true
      end
    end

    describe '#max_pending_age' do
      it 'returns configured max age' do
        expect(subject.max_pending_age).to eq(7200)
      end

      it 'returns default max age when not configured' do
        config[:config].delete('max_pending_age')
        expect(subject.max_pending_age).to eq(7200)
      end
    end

    describe '#purge_pending_queue' do
      let(:pool) { 'test-pool' }
      let(:old_vm) { 'vm-old' }
      let(:new_vm) { 'vm-new' }

      before(:each) do
        redis_connection_pool.with do |redis_connection|
          # Old VM (3 hours old, exceeds 2 hour threshold)
          redis_connection.sadd("vmpooler__pending__#{pool}", old_vm)
          redis_connection.hset("vmpooler__vm__#{old_vm}", 'clone', (Time.now - 10800).to_s)
          
          # New VM (30 minutes old, within threshold)
          redis_connection.sadd("vmpooler__pending__#{pool}", new_vm)
          redis_connection.hset("vmpooler__vm__#{new_vm}", 'clone', (Time.now - 1800).to_s)
        end
      end

      context 'when not in dry-run mode' do
        it 'purges stale pending VMs' do
          redis_connection_pool.with do |redis_connection|
            purged_count = subject.purge_pending_queue(pool, redis_connection)
            
            expect(purged_count).to eq(1)
            expect(redis_connection.sismember("vmpooler__pending__#{pool}", old_vm)).to be false
            expect(redis_connection.sismember("vmpooler__pending__#{pool}", new_vm)).to be true
          end
        end

        it 'moves purged VMs to DLQ' do
          redis_connection_pool.with do |redis_connection|
            expect(subject).to receive(:move_to_dlq).with(
              old_vm, pool, 'pending', 'Purge', anything, redis_connection, anything
            )
            
            subject.purge_pending_queue(pool, redis_connection)
          end
        end

        it 'increments purge metrics' do
          redis_connection_pool.with do |redis_connection|
            expect(metrics).to receive(:increment).with("purge.pending.#{pool}.count")
            
            subject.purge_pending_queue(pool, redis_connection)
          end
        end
      end

      context 'when in dry-run mode' do
        before { config[:config]['purge_dry_run'] = true }

        it 'detects but does not purge stale VMs' do
          redis_connection_pool.with do |redis_connection|
            purged_count = subject.purge_pending_queue(pool, redis_connection)
            
            expect(purged_count).to eq(1)
            expect(redis_connection.sismember("vmpooler__pending__#{pool}", old_vm)).to be true
          end
        end

        it 'does not move to DLQ' do
          redis_connection_pool.with do |redis_connection|
            expect(subject).not_to receive(:move_to_dlq)
            
            subject.purge_pending_queue(pool, redis_connection)
          end
        end
      end
    end

    describe '#purge_ready_queue' do
      let(:pool) { 'test-pool' }
      let(:old_vm) { 'vm-old-ready' }
      let(:new_vm) { 'vm-new-ready' }

      before(:each) do
        redis_connection_pool.with do |redis_connection|
          # Old VM (25 hours old, exceeds 24 hour threshold)
          redis_connection.sadd("vmpooler__ready__#{pool}", old_vm)
          redis_connection.hset("vmpooler__vm__#{old_vm}", 'ready', (Time.now - 90000).to_s)
          
          # New VM (2 hours old, within threshold)
          redis_connection.sadd("vmpooler__ready__#{pool}", new_vm)
          redis_connection.hset("vmpooler__vm__#{new_vm}", 'ready', (Time.now - 7200).to_s)
        end
      end

      it 'moves stale ready VMs to completed queue' do
        redis_connection_pool.with do |redis_connection|
          purged_count = subject.purge_ready_queue(pool, redis_connection)
          
          expect(purged_count).to eq(1)
          expect(redis_connection.sismember("vmpooler__ready__#{pool}", old_vm)).to be false
          expect(redis_connection.sismember("vmpooler__completed__#{pool}", old_vm)).to be true
          expect(redis_connection.sismember("vmpooler__ready__#{pool}", new_vm)).to be true
        end
      end
    end

    describe '#purge_completed_queue' do
      let(:pool) { 'test-pool' }
      let(:old_vm) { 'vm-old-completed' }
      let(:new_vm) { 'vm-new-completed' }

      before(:each) do
        redis_connection_pool.with do |redis_connection|
          # Old VM (2 hours old, exceeds 1 hour threshold)
          redis_connection.sadd("vmpooler__completed__#{pool}", old_vm)
          redis_connection.hset("vmpooler__vm__#{old_vm}", 'destroy', (Time.now - 7200).to_s)
          
          # New VM (30 minutes old, within threshold)
          redis_connection.sadd("vmpooler__completed__#{pool}", new_vm)
          redis_connection.hset("vmpooler__vm__#{new_vm}", 'destroy', (Time.now - 1800).to_s)
        end
      end

      it 'removes stale completed VMs' do
        redis_connection_pool.with do |redis_connection|
          purged_count = subject.purge_completed_queue(pool, redis_connection)
          
          expect(purged_count).to eq(1)
          expect(redis_connection.sismember("vmpooler__completed__#{pool}", old_vm)).to be false
          expect(redis_connection.sismember("vmpooler__completed__#{pool}", new_vm)).to be true
        end
      end
    end
  end

  describe 'Health Checks' do
    describe '#health_check_enabled?' do
      it 'returns true when health_check_enabled is true in config' do
        expect(subject.health_check_enabled?).to be true
      end

      it 'returns false when health_check_enabled is false in config' do
        config[:config]['health_check_enabled'] = false
        expect(subject.health_check_enabled?).to be false
      end
    end

    describe '#health_thresholds' do
      it 'returns configured thresholds' do
        thresholds = subject.health_thresholds
        expect(thresholds['pending_queue_max']).to eq(100)
        expect(thresholds['stuck_vm_age_threshold']).to eq(7200)
      end

      it 'merges with defaults when partially configured' do
        config[:config]['health_thresholds'] = { 'pending_queue_max' => 200 }
        thresholds = subject.health_thresholds
        
        expect(thresholds['pending_queue_max']).to eq(200)
        expect(thresholds['ready_queue_max']).to eq(500) # default
      end
    end

    describe '#calculate_queue_ages' do
      let(:pool) { 'test-pool' }
      let(:vm1) { 'vm-1' }
      let(:vm2) { 'vm-2' }
      let(:vm3) { 'vm-3' }

      before(:each) do
        redis_connection_pool.with do |redis_connection|
          redis_connection.hset("vmpooler__vm__#{vm1}", 'clone', (Time.now - 3600).to_s)
          redis_connection.hset("vmpooler__vm__#{vm2}", 'clone', (Time.now - 7200).to_s)
          redis_connection.hset("vmpooler__vm__#{vm3}", 'clone', (Time.now - 1800).to_s)
        end
      end

      it 'calculates ages for all VMs' do
        redis_connection_pool.with do |redis_connection|
          vms = [vm1, vm2, vm3]
          ages = subject.calculate_queue_ages(vms, 'clone', redis_connection)
          
          expect(ages.length).to eq(3)
          expect(ages[0]).to be_within(5).of(3600)
          expect(ages[1]).to be_within(5).of(7200)
          expect(ages[2]).to be_within(5).of(1800)
        end
      end

      it 'skips VMs with missing timestamps' do
        redis_connection_pool.with do |redis_connection|
          vms = [vm1, 'vm-nonexistent', vm3]
          ages = subject.calculate_queue_ages(vms, 'clone', redis_connection)
          
          expect(ages.length).to eq(2)
        end
      end
    end

    describe '#determine_health_status' do
      let(:base_metrics) do
        {
          'queues' => {
            'test-pool' => {
              'pending' => { 'size' => 10, 'stuck_count' => 2 },
              'ready' => { 'size' => 50 }
            }
          },
          'errors' => {
            'dlq_total_size' => 50,
            'stuck_vm_count' => 2
          }
        }
      end

      it 'returns healthy when all metrics are within thresholds' do
        status = subject.determine_health_status(base_metrics)
        expect(status).to eq('healthy')
      end

      it 'returns degraded when DLQ size exceeds warning threshold' do
        metrics = base_metrics.dup
        metrics['errors']['dlq_total_size'] = 150
        
        status = subject.determine_health_status(metrics)
        expect(status).to eq('degraded')
      end

      it 'returns unhealthy when DLQ size exceeds critical threshold' do
        metrics = base_metrics.dup
        metrics['errors']['dlq_total_size'] = 1500
        
        status = subject.determine_health_status(metrics)
        expect(status).to eq('unhealthy')
      end

      it 'returns degraded when pending queue exceeds warning threshold' do
        metrics = base_metrics.dup
        metrics['queues']['test-pool']['pending']['size'] = 120
        
        status = subject.determine_health_status(metrics)
        expect(status).to eq('degraded')
      end

      it 'returns unhealthy when pending queue exceeds critical threshold' do
        metrics = base_metrics.dup
        metrics['queues']['test-pool']['pending']['size'] = 250
        
        status = subject.determine_health_status(metrics)
        expect(status).to eq('unhealthy')
      end

      it 'returns unhealthy when stuck VM count exceeds critical threshold' do
        metrics = base_metrics.dup
        metrics['errors']['stuck_vm_count'] = 60
        
        status = subject.determine_health_status(metrics)
        expect(status).to eq('unhealthy')
      end
    end

    describe '#push_health_metrics' do
      let(:metrics_data) do
        {
          'queues' => {
            'test-pool' => {
              'pending' => { 'size' => 10, 'oldest_age' => 3600, 'stuck_count' => 2 },
              'ready' => { 'size' => 50, 'oldest_age' => 7200 },
              'completed' => { 'size' => 5 }
            }
          },
          'tasks' => {
            'clone' => { 'active' => 3 },
            'ondemand' => { 'active' => 2, 'pending' => 5 }
          },
          'errors' => {
            'dlq_total_size' => 25,
            'stuck_vm_count' => 2,
            'orphaned_metadata_count' => 3
          }
        }
      end

      it 'pushes status metric' do
        expect(metrics).to receive(:gauge).with('health.status', 0)
        
        subject.push_health_metrics(metrics_data, 'healthy')
      end

      it 'pushes error metrics' do
        expect(metrics).to receive(:gauge).with('health.dlq.total_size', 25)
        expect(metrics).to receive(:gauge).with('health.stuck_vms.count', 2)
        expect(metrics).to receive(:gauge).with('health.orphaned_metadata.count', 3)
        
        subject.push_health_metrics(metrics_data, 'healthy')
      end

      it 'pushes per-pool queue metrics' do
        expect(metrics).to receive(:gauge).with('health.queue.test-pool.pending.size', 10)
        expect(metrics).to receive(:gauge).with('health.queue.test-pool.pending.oldest_age', 3600)
        expect(metrics).to receive(:gauge).with('health.queue.test-pool.pending.stuck_count', 2)
        expect(metrics).to receive(:gauge).with('health.queue.test-pool.ready.size', 50)
        
        subject.push_health_metrics(metrics_data, 'healthy')
      end

      it 'pushes task metrics' do
        expect(metrics).to receive(:gauge).with('health.tasks.clone.active', 3)
        expect(metrics).to receive(:gauge).with('health.tasks.ondemand.active', 2)
        expect(metrics).to receive(:gauge).with('health.tasks.ondemand.pending', 5)
        
        subject.push_health_metrics(metrics_data, 'healthy')
      end
    end
  end
end
