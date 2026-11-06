# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/pool_manager'

describe 'Vmpooler::PoolManager - purge and health cycles' do
  let(:recording_logger) do
    Class.new do
      def lines
        @lines ||= []
      end

      def log(_level, string)
        lines << string
      end
    end
  end
  let(:logger) { recording_logger.new }
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:redis_connection_pool) do
    Vmpooler::PoolManager::GenericConnectionPool.new(
      metrics: metrics, connpool_type: 'redis_connection_pool', connpool_provider: 'testprovider', size: 1, timeout: 5
    ) { redis }
  end
  let(:purge_dry_run) { false }
  let(:config) do
    {
      config: {
        'task_limit' => 10,
        'vm_checktime' => 1,
        'vm_lifetime' => 12,
        'prefix' => 'pooler-',
        'dlq_enabled' => true,
        'purge_enabled' => true,
        'purge_dry_run' => purge_dry_run,
        'max_orphaned_age' => 3600,
        'health_check_enabled' => true,
        'health_thresholds' => { 'stuck_vm_age_threshold' => 7200 }
      },
      providers: { dummy: {} },
      pools: [{ 'name' => 'test-pool', 'size' => 5, 'provider' => 'dummy' }]
    }
  end
  let(:pool) { 'test-pool' }

  subject { Vmpooler::PoolManager.new(config, logger, redis_connection_pool, metrics) }

  def with_redis(&block)
    redis_connection_pool.with(&block)
  end

  describe '#purge_orphaned_metadata' do
    let(:old) { (Time.now - 7200).to_s }

    before do
      with_redis do |r|
        # in no queue and old: orphaned
        r.hset('vmpooler__vm__orphan', 'pool', pool)
        r.hset('vmpooler__vm__orphan', 'clone', old)
        # in no queue but recent: kept
        r.hset('vmpooler__vm__fresh', 'pool', pool)
        r.hset('vmpooler__vm__fresh', 'clone', Time.now.to_s)
        # old but still in a queue: kept
        r.hset('vmpooler__vm__queued', 'pool', pool)
        r.hset('vmpooler__vm__queued', 'clone', old)
        r.sadd("vmpooler__running__#{pool}", 'queued')
        # no pool recorded, and no clone time: ignored
        r.hset('vmpooler__vm__nopool', 'clone', old)
        r.hset('vmpooler__vm__noclone', 'pool', pool)
        # clone time that cannot be parsed: logged and skipped
        r.hset('vmpooler__vm__garbled', 'pool', pool)
        r.hset('vmpooler__vm__garbled', 'clone', 'not a time')
      end
    end

    it 'expires the metadata of old VMs that are in no queue' do
      with_redis do |r|
        expect(subject.purge_orphaned_metadata(r)).to eq(1)

        expect(r.ttl('vmpooler__vm__orphan')).to be_between(1, 3600)
        expect(r.ttl('vmpooler__vm__queued')).to eq(-1)
        expect(r.ttl('vmpooler__vm__fresh')).to eq(-1)
      end
    end

    it 'counts the purge in metrics' do
      expect(metrics).to receive(:increment).with('vmpooler_purge.orphaned.count')

      with_redis { |r| subject.purge_orphaned_metadata(r) }
    end

    it 'logs the VM it could not check, and carries on' do
      with_redis { |r| subject.purge_orphaned_metadata(r) }

      expect(logger.lines.join).to match(/Error checking orphaned metadata 'vmpooler__vm__garbled'/)
    end

    context 'in dry-run mode' do
      let(:purge_dry_run) { true }

      it 'counts the VM but leaves its metadata alone' do
        with_redis do |r|
          expect(subject.purge_orphaned_metadata(r)).to eq(1)

          expect(r.ttl('vmpooler__vm__orphan')).to eq(-1)
        end
        expect(logger.lines.join).to match(/Would purge orphaned metadata for 'orphan'/)
      end
    end
  end

  describe '#count_orphaned_metadata' do
    it 'counts VM records that are in no queue, and skips ones with no pool' do
      with_redis do |r|
        r.hset('vmpooler__vm__orphan', 'pool', pool)
        r.hset('vmpooler__vm__nopool', 'clone', 'x')
        r.hset('vmpooler__vm__queued', 'pool', pool)
        r.sadd("vmpooler__pending__#{pool}", 'queued')

        expect(subject.count_orphaned_metadata(r)).to eq(1)
      end
    end
  end

  describe '#purge_stale_queue_entries' do
    before do
      with_redis do |r|
        r.sadd("vmpooler__pending__#{pool}", 'stale-pending')
        r.hset('vmpooler__vm__stale-pending', 'clone', (Time.now - 10_800).to_s)
        r.sadd("vmpooler__ready__#{pool}", 'stale-ready')
        r.hset('vmpooler__vm__stale-ready', 'ready', (Time.now - 172_800).to_s)
        r.sadd("vmpooler__completed__#{pool}", 'stale-completed')
        r.hset('vmpooler__vm__stale-completed', 'destroy', (Time.now - 7200).to_s)
        r.hset('vmpooler__vm__orphan', 'pool', pool)
        r.hset('vmpooler__vm__orphan', 'clone', (Time.now - 7200).to_s)
      end
    end

    it 'purges every kind of stale entry and logs the total' do
      subject.purge_stale_queue_entries.join

      with_redis do |r|
        expect(r.sismember("vmpooler__pending__#{pool}", 'stale-pending')).to be false
        expect(r.sismember("vmpooler__ready__#{pool}", 'stale-ready')).to be false
        expect(r.sismember("vmpooler__completed__#{pool}", 'stale-completed')).to be false
      end
      expect(logger.lines.join).to match(/Completed purge cycle .*: 4 entries purged/)
    end

    it 'does nothing when purging is off' do
      config[:config]['purge_enabled'] = false

      expect(subject.purge_stale_queue_entries).to be_nil
    end

    it 'logs a failure instead of raising' do
      allow(subject).to receive(:purge_pending_queue).and_raise('redis went away')

      expect { subject.purge_stale_queue_entries.join }.not_to raise_error
      expect(logger.lines.join).to match(/Failed during purge cycle: redis went away/)
    end
  end

  describe '#calculate_health_metrics' do
    before do
      with_redis do |r|
        r.sadd("vmpooler__pending__#{pool}", %w[p1 p2])
        r.hset('vmpooler__vm__p1', 'clone', (Time.now - 10_000).to_s)
        r.hset('vmpooler__vm__p2', 'clone', (Time.now - 100).to_s)
        r.sadd("vmpooler__ready__#{pool}", 'r1')
        r.hset('vmpooler__vm__r1', 'ready', (Time.now - 60).to_s)
        r.sadd("vmpooler__completed__#{pool}", 'c1')
        r.set('vmpooler__tasks__clone', '3')
        r.set('vmpooler__tasks__ondemandclone', '2')
        r.zadd('vmpooler__odcreate__task', 1, 'odc1')
        r.zadd('vmpooler__dlq__pending', 1, 'dead1')
        r.zadd('vmpooler__dlq__clone', 1, 'dead2')
        r.hset('vmpooler__vm__orphan', 'pool', pool)
      end
    end

    it 'reports the queues, tasks and errors' do
      result = with_redis { |r| subject.calculate_health_metrics(r) }

      expect(result['queues'][pool]['pending']).to include('size' => 2, 'stuck_count' => 1)
      expect(result['queues'][pool]['pending']['oldest_age']).to be >= 10_000
      expect(result['queues'][pool]['ready']['size']).to eq(1)
      expect(result['queues'][pool]['completed']).to eq('size' => 1)
      expect(result['tasks']['clone']).to eq('active' => 3)
      expect(result['tasks']['ondemand']).to eq('active' => 2, 'pending' => 1)
      expect(result['queues']['dlq']).to eq('pending' => { 'size' => 1 }, 'clone' => { 'size' => 1 })
      expect(result['errors']).to include('dlq_total_size' => 2, 'stuck_vm_count' => 1)
      expect(result['errors']['orphaned_metadata_count']).to be >= 1
    end

    it 'leaves out the dead-letter queues when they are off' do
      config[:config]['dlq_enabled'] = false

      result = with_redis { |r| subject.calculate_health_metrics(r) }

      expect(result['queues']).not_to have_key('dlq')
      expect(result['errors']['dlq_total_size']).to eq(0)
    end

    it 'reports zero ages for empty queues' do
      with_redis(&:flushdb)

      result = with_redis { |r| subject.calculate_health_metrics(r) }

      expect(result['queues'][pool]['pending']).to eq('size' => 0, 'oldest_age' => 0, 'avg_age' => 0, 'stuck_count' => 0)
    end
  end

  describe '#calculate_queue_ages' do
    it 'skips VMs with no timestamp or an unparseable one' do
      with_redis do |r|
        r.hset('vmpooler__vm__good', 'clone', (Time.now - 30).to_s)
        r.hset('vmpooler__vm__bad', 'clone', 'garbage')

        ages = subject.calculate_queue_ages(%w[good bad missing], 'clone', r)

        expect(ages.size).to eq(1)
        expect(ages.first).to be_between(29, 40)
      end
    end
  end

  describe '#check_queue_health' do
    before do
      with_redis { |r| r.sadd("vmpooler__pending__#{pool}", 'p1') }
    end

    it 'stores the health picture in redis' do
      subject.check_queue_health.join

      with_redis do |r|
        expect(r.hget('vmpooler__health', 'status')).to eq('healthy')
        expect(JSON.parse(r.hget('vmpooler__health', 'metrics'))['queues'][pool]['pending']['size']).to eq(1)
        expect(r.hget('vmpooler__health', 'last_check')).not_to be_nil
        expect(r.ttl('vmpooler__health')).to be_between(1, 3600)
      end
      expect(logger.lines.join).to match(/Status: HEALTHY \| Queues: P=1 R=0 C=0/)
    end

    it 'does nothing when health checks are off' do
      config[:config]['health_check_enabled'] = false

      expect(subject.check_queue_health).to be_nil
    end

    it 'logs a failure instead of raising' do
      allow(subject).to receive(:calculate_health_metrics).and_raise('boom')

      expect { subject.check_queue_health.join }.not_to raise_error
      expect(logger.lines.join).to match(/Failed during health check: boom/)
    end
  end

  describe '#log_health_summary' do
    let(:summary) do
      { 'queues' => { pool => { 'pending' => { 'size' => 4 } }, 'dlq' => { 'x' => { 'size' => 9 } } },
        'errors' => { 'dlq_total_size' => 9, 'stuck_vm_count' => 1, 'orphaned_metadata_count' => 2 } }
    end

    it 'treats a queue it has no numbers for as empty, and ignores the dlq entry' do
      subject.log_health_summary(summary, 'degraded')

      expect(logger.lines.join).to match(/Status: DEGRADED \| Queues: P=4 R=0 C=0 \| DLQ=9 \| Stuck=1 \| Orphaned=2/)
    end
  end

  describe '#determine_health_status' do
    def status_for(pending: 0, ready: 0, dlq: 0, stuck: 0)
      subject.determine_health_status(
        'queues' => { pool => { 'pending' => { 'size' => pending }, 'ready' => { 'size' => ready } }, 'dlq' => {} },
        'errors' => { 'dlq_total_size' => dlq, 'stuck_vm_count' => stuck }
      )
    end

    it 'is unhealthy when a queue is more than double its limit' do
      expect(status_for(pending: 201)).to eq('unhealthy')
      expect(status_for(ready: 1001)).to eq('unhealthy')
    end

    it 'is degraded when a queue or the stuck count passes its warning level' do
      expect(status_for(pending: 101)).to eq('degraded')
      expect(status_for(ready: 501)).to eq('degraded')
      expect(status_for(stuck: 11)).to eq('degraded')
      expect(status_for(dlq: 101)).to eq('degraded')
    end

    it 'is unhealthy when the stuck count passes the critical level' do
      expect(status_for(stuck: 51)).to eq('unhealthy')
    end

    it 'copes with a pool that has no queue figures' do
      result = subject.determine_health_status(
        'queues' => { pool => {} },
        'errors' => { 'dlq_total_size' => 0, 'stuck_vm_count' => 0 }
      )

      expect(result).to eq('healthy')
    end
  end
end
