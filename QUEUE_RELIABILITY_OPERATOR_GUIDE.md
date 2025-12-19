# Queue Reliability Features - Operator Guide

## Overview

This guide covers the Dead-Letter Queue (DLQ), Auto-Purge, and Health Check features added to VMPooler for improved queue reliability and observability.

## Features

### 1. Dead-Letter Queue (DLQ)

The DLQ captures failed VM creation attempts and queue transitions, providing visibility into failures without losing data.

**What gets captured:**
- VMs that fail during clone operations
- VMs that timeout in pending queue
- VMs that become unreachable in ready queue
- Any permanent errors (template not found, permission denied, etc.)

**Benefits:**
- Failed VMs are not lost - they're moved to DLQ for analysis
- Complete failure context (error message, timestamp, retry count, request ID)
- TTL-based expiration prevents unbounded growth
- Size limiting prevents memory issues

**Configuration:**
```yaml
:config:
  dlq_enabled: true
  dlq_ttl: 168  # hours (7 days)
  dlq_max_entries: 10000  # per DLQ queue
```

**Querying DLQ via Redis CLI:**
```bash
# View all pending DLQ entries
redis-cli ZRANGE vmpooler__dlq__pending 0 -1

# View DLQ entries with scores (timestamps)
redis-cli ZRANGE vmpooler__dlq__pending 0 -1 WITHSCORES

# Get DLQ size
redis-cli ZCARD vmpooler__dlq__pending

# View recent failures (last 10)
redis-cli ZREVRANGE vmpooler__dlq__clone 0 9

# View entries older than 1 hour (timestamp in seconds)
redis-cli ZRANGEBYSCORE vmpooler__dlq__pending -inf $(date -d '1 hour ago' +%s)
```

**DLQ Keys:**
- `vmpooler__dlq__pending` - Failed pending VMs
- `vmpooler__dlq__clone` - Failed clone operations
- `vmpooler__dlq__ready` - Failed ready queue VMs
- `vmpooler__dlq__tasks` - Failed tasks

**Entry Format:**
Each DLQ entry contains:
```json
{
  "vm": "pooler-happy-elephant",
  "pool": "centos-7-x86_64",
  "queue_from": "pending",
  "error_class": "StandardError",
  "error_message": "template centos-7-template does not exist",
  "failed_at": "2024-01-15T10:30:00Z",
  "retry_count": 3,
  "request_id": "req-abc123",
  "pool_alias": "centos-7"
}
```

### 2. Auto-Purge

Automatically removes stale entries from queues to prevent resource leaks and maintain queue health.

**What gets purged:**
- **Pending VMs**: Stuck in pending queue longer than `max_pending_age`
- **Ready VMs**: Idle in ready queue longer than `max_ready_age`
- **Completed VMs**: In completed queue longer than `max_completed_age`
- **Orphaned Metadata**: VM metadata without corresponding queue entry

**Benefits:**
- Prevents queue bloat from stuck/forgotten VMs
- Automatically cleans up after process crashes or bugs
- Configurable thresholds per environment
- Dry-run mode for safe testing

**Configuration:**
```yaml
:config:
  purge_enabled: true
  purge_interval: 3600  # seconds (1 hour) - how often to run
  purge_dry_run: false  # set to true to log but not purge
  
  # Age thresholds (in seconds)
  max_pending_age: 7200   # 2 hours
  max_ready_age: 86400    # 24 hours
  max_completed_age: 3600 # 1 hour
  max_orphaned_age: 86400 # 24 hours
```

**Testing Purge (Dry-Run Mode):**
```yaml
:config:
  purge_enabled: true
  purge_dry_run: true  # Logs what would be purged without actually purging
  max_pending_age: 600  # Use shorter thresholds for testing
```

Watch logs for:
```
[*] [purge][dry-run] Would purge stale pending VM 'pooler-happy-elephant' (age: 3650s, max: 600s)
```

**Monitoring Purge:**
Check logs for purge cycles:
```
[*] [purge] Starting stale queue entry purge cycle
[!] [purge] Purged stale pending VM 'pooler-sad-dog' from 'centos-7-x86_64' (age: 7250s)
[!] [purge] Moved stale ready VM 'pooler-angry-cat' from 'ubuntu-2004-x86_64' to completed (age: 90000s)
[*] [purge] Completed purge cycle in 2.34s: 12 entries purged
```

### 3. Health Checks

Monitors queue health and exposes metrics for alerting and dashboards.

**What gets monitored:**
- Queue sizes (pending, ready, completed)
- Queue ages (oldest VM, average age)
- Stuck VMs (VMs in pending queue longer than threshold)
- DLQ size
- Orphaned metadata count
- Task queue sizes (clone, on-demand)
- Overall health status (healthy/degraded/unhealthy)

**Benefits:**
- Proactive detection of queue issues
- Metrics for alerting and dashboards
- Historical health tracking
- API endpoint for health status

**Configuration:**
```yaml
:config:
  health_check_enabled: true
  health_check_interval: 300  # seconds (5 minutes)
  
  health_thresholds:
    pending_queue_max: 100
    ready_queue_max: 500
    dlq_max_warning: 100
    dlq_max_critical: 1000
    stuck_vm_age_threshold: 7200  # 2 hours
    stuck_vm_max_warning: 10
    stuck_vm_max_critical: 50
```

**Health Status Levels:**
- **Healthy**: All metrics within normal thresholds
- **Degraded**: Some metrics elevated but functional (DLQ > warning, queue sizes elevated)
- **Unhealthy**: Critical thresholds exceeded (DLQ > critical, many stuck VMs, queues backed up)

**Viewing Health Status:**

Via Redis:
```bash
# Get current health status
redis-cli HGETALL vmpooler__health

# Get specific health metric
redis-cli HGET vmpooler__health status
redis-cli HGET vmpooler__health last_check
```

Via Logs:
```
[*] [health] Status: HEALTHY | Queues: P=45 R=230 C=12 | DLQ=25 | Stuck=3 | Orphaned=5
```

**Exposed Metrics:**

The following metrics are pushed to the metrics system (Prometheus, Graphite, etc.):

```
# Health status (0=healthy, 1=degraded, 2=unhealthy)
vmpooler.health.status

# Error metrics
vmpooler.health.dlq.total_size
vmpooler.health.stuck_vms.count
vmpooler.health.orphaned_metadata.count

# Per-pool queue metrics
vmpooler.health.queue.<pool_name>.pending.size
vmpooler.health.queue.<pool_name>.pending.oldest_age
vmpooler.health.queue.<pool_name>.pending.stuck_count
vmpooler.health.queue.<pool_name>.ready.size
vmpooler.health.queue.<pool_name>.ready.oldest_age
vmpooler.health.queue.<pool_name>.completed.size

# DLQ metrics
vmpooler.health.dlq.<queue_type>.size

# Task metrics
vmpooler.health.tasks.clone.active
vmpooler.health.tasks.ondemand.active
vmpooler.health.tasks.ondemand.pending
```

## Common Scenarios

### Scenario 1: Investigating Failed VM Requests

**Problem:** User reports VM request failed.

**Steps:**
1. Check DLQ for the request:
   ```bash
   redis-cli ZRANGE vmpooler__dlq__pending 0 -1 | grep "req-abc123"
   redis-cli ZRANGE vmpooler__dlq__clone 0 -1 | grep "req-abc123"
   ```

2. Parse the JSON entry to see failure details:
   ```bash
   redis-cli ZRANGE vmpooler__dlq__clone 0 -1 | grep "req-abc123" | jq .
   ```

3. Common failure reasons:
   - `template does not exist` - Template missing or renamed in provider
   - `permission denied` - VMPooler lacks permissions to clone template
   - `timeout` - VM failed to become ready within timeout period
   - `failed to obtain IP` - Network/DHCP issue

### Scenario 2: Queue Backup

**Problem:** Pending queue growing, VMs not moving to ready.

**Steps:**
1. Check health status:
   ```bash
   redis-cli HGET vmpooler__health status
   ```

2. Check pending queue metrics:
   ```bash
   # View stuck VMs
   redis-cli HGET vmpooler__health stuck_vm_count
   
   # Check oldest VM age
   redis-cli SMEMBERS vmpooler__pending__centos-7-x86_64 | head -1 | xargs -I {} redis-cli HGET vmpooler__vm__{} clone
   ```

3. Check DLQ for recent failures:
   ```bash
   redis-cli ZREVRANGE vmpooler__dlq__clone 0 9
   ```

4. Common causes:
   - Provider errors (vCenter unreachable, no resources)
   - Network issues (can't reach VMs, no DHCP)
   - Configuration issues (wrong template name, bad credentials)

### Scenario 3: High DLQ Size

**Problem:** DLQ size growing, indicating persistent failures.

**Steps:**
1. Check DLQ size:
   ```bash
   redis-cli ZCARD vmpooler__dlq__pending
   redis-cli ZCARD vmpooler__dlq__clone
   ```

2. Identify common failure patterns:
   ```bash
   redis-cli ZRANGE vmpooler__dlq__clone 0 -1 | jq -r '.error_message' | sort | uniq -c | sort -rn
   ```

3. Fix underlying issues (template exists, permissions, network)

4. If issues resolved, DLQ entries will expire after TTL (default 7 days)

### Scenario 4: Testing Configuration Changes

**Problem:** Want to test new purge thresholds without affecting production.

**Steps:**
1. Enable dry-run mode:
   ```yaml
   :config:
     purge_dry_run: true
     max_pending_age: 3600  # Test with 1 hour
   ```

2. Monitor logs for purge detections:
   ```bash
   tail -f vmpooler.log | grep "purge.*dry-run"
   ```

3. Verify detection is correct

4. Disable dry-run when ready:
   ```yaml
   :config:
     purge_dry_run: false
   ```

### Scenario 5: Alerting on Queue Health

**Problem:** Want to be notified when queues are unhealthy.

**Steps:**
1. Set up Prometheus alerts based on health metrics:
   ```yaml
   - alert: VMPoolerUnhealthy
     expr: vmpooler_health_status >= 2
     for: 10m
     annotations:
       summary: "VMPooler is unhealthy"
   
   - alert: VMPoolerHighDLQ
     expr: vmpooler_health_dlq_total_size > 500
     for: 30m
     annotations:
       summary: "VMPooler DLQ size is high"
   
   - alert: VMPoolerStuckVMs
     expr: vmpooler_health_stuck_vms_count > 20
     for: 15m
     annotations:
       summary: "Many VMs stuck in pending queue"
   ```

## Troubleshooting

### DLQ Not Capturing Failures

**Check:**
1. Is DLQ enabled? `redis-cli HGET vmpooler__config dlq_enabled`
2. Are failures actually occurring? Check logs for error messages
3. Is Redis accessible? `redis-cli PING`

### Purge Not Running

**Check:**
1. Is purge enabled? Check config `purge_enabled: true`
2. Check logs for purge thread startup: `[*] [purge] Starting stale queue entry purge cycle`
3. Is purge interval too long? Default is 1 hour
4. Check thread status in logs: `[!] [queue_purge] worker thread died`

### Health Check Not Updating

**Check:**
1. Is health check enabled? Check config `health_check_enabled: true`
2. Check last update time: `redis-cli HGET vmpooler__health last_check`
3. Check logs for health check runs: `[*] [health] Status:`
4. Check thread status: `[!] [health_check] worker thread died`

### Metrics Not Appearing

**Check:**
1. Is metrics system configured? Check `:statsd` or `:graphite` config
2. Are metrics being sent? Check logs for metric sends
3. Check firewall/network to metrics server
4. Test metrics manually: `redis-cli HGETALL vmpooler__health`

## Best Practices

### Development/Testing Environments
- Enable DLQ with shorter TTL (24-48 hours)
- Enable purge with dry-run mode initially
- Use aggressive purge thresholds (30min pending, 6hr ready)
- Enable health checks with 1-minute interval
- Monitor logs closely for issues

### Production Environments
- Enable DLQ with 7-day TTL
- Enable purge after testing in dev
- Use conservative purge thresholds (2hr pending, 24hr ready)
- Enable health checks with 5-minute interval
- Set up alerting based on health metrics
- Monitor DLQ size and set alerts (>500 = investigate)

### Capacity Planning
- Monitor queue sizes during peak times
- Adjust thresholds based on actual usage patterns
- Review DLQ entries weekly for systemic issues
- Track purge counts to identify resource leaks

### Debugging
- Keep DLQ TTL long enough for investigation (7+ days)
- Use dry-run mode when testing threshold changes
- Correlate DLQ entries with provider logs
- Check health metrics before and after changes

## Migration Guide

### Enabling Features in Existing Deployment

1. **Phase 1: Enable DLQ**
   - Add DLQ config with conservative TTL
   - Monitor DLQ size and entry patterns
   - Verify no performance impact
   - Adjust TTL as needed

2. **Phase 2: Enable Health Checks**
   - Add health check config
   - Verify metrics are exposed
   - Set up dashboards
   - Configure alerting

3. **Phase 3: Enable Purge (Dry-Run)**
   - Add purge config with `purge_dry_run: true`
   - Monitor logs for purge detections
   - Verify thresholds are appropriate
   - Adjust thresholds based on observations

4. **Phase 4: Enable Purge (Live)**
   - Set `purge_dry_run: false`
   - Monitor queue sizes and purge counts
   - Watch for unexpected VM removal
   - Adjust thresholds if needed

## Performance Considerations

- **DLQ**: Minimal overhead, uses Redis sorted sets
- **Purge**: Runs in background thread, iterates through queues
- **Health Checks**: Lightweight, caches metrics between runs

Expected impact:
- Redis memory: +1-5MB for DLQ (depends on DLQ size)
- CPU: +1-2% during purge/health check cycles
- Network: Minimal, only metric pushes

## Support

For issues or questions:
1. Check logs for error messages
2. Review DLQ entries for failure patterns
3. Check health status and metrics
4. Open issue on GitHub with logs and config

