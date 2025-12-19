# Redis Queue Reliability Features

## Overview
This document describes the implementation of dead-letter queues (DLQ), auto-purge mechanisms, and health checks for VMPooler Redis queues.

## Background

### Current Queue Structure
VMPooler uses Redis sets and sorted sets for queue management:

- **Pool Queues** (Sets): `vmpooler__pending__#{pool}`, `vmpooler__ready__#{pool}`, `vmpooler__running__#{pool}`, `vmpooler__completed__#{pool}`, `vmpooler__discovered__#{pool}`, `vmpooler__migrating__#{pool}`
- **Task Queues** (Sorted Sets): `vmpooler__odcreate__task` (on-demand creation tasks), `vmpooler__provisioning__processing`
- **Task Queues** (Sets): `vmpooler__tasks__disk`, `vmpooler__tasks__snapshot`, `vmpooler__tasks__snapshot-revert`
- **VM Metadata** (Hashes): `vmpooler__vm__#{vm}` - contains clone time, IP, template, pool, domain, request_id, pool_alias, error details
- **Request Metadata** (Hashes): `vmpooler__odrequest__#{request_id}` - contains status, retry_count, token info

### Current Error Handling
- Permanent errors (e.g., template not found) are detected in `_clone_vm` rescue block
- Failed VMs are removed from pending queue
- Request status is set to 'failed' and re-queue is prevented in outer `clone_vm` rescue block
- VM metadata expires after data_ttl hours

### Problem Areas
1. **Lost visibility**: Failed messages are removed but no centralized tracking
2. **Stale data**: VMs stuck in queues due to process crashes or bugs
3. **No monitoring**: No automated way to detect queue health issues
4. **Manual cleanup**: Operators must manually identify and clean stale entries

## Feature Requirements

### 1. Dead-Letter Queue (DLQ)

#### Purpose
Capture failed VM creation requests for visibility, debugging, and potential retry/recovery.

#### Design

**DLQ Structure:**
```
vmpooler__dlq__pending       # Failed pending VMs (sorted set, scored by failure timestamp)
vmpooler__dlq__clone         # Failed clone operations (sorted set)
vmpooler__dlq__ready         # Failed ready queue VMs (sorted set)
vmpooler__dlq__tasks         # Failed tasks (hash of task_type -> failed items)
```

**DLQ Entry Format:**
```json
{
  "vm": "vm-name-abc123",
  "pool": "pool-name",
  "queue_from": "pending",
  "error_class": "StandardError",
  "error_message": "template does not exist",
  "failed_at": "2024-01-15T10:30:00Z",
  "retry_count": 3,
  "request_id": "req-123456",
  "pool_alias": "centos-7"
}
```

**Configuration:**
```yaml
:redis:
  dlq_enabled: true
  dlq_ttl: 168  # hours (7 days)
  dlq_max_entries: 10000  # per DLQ queue
```

**Implementation Points:**
- `fail_pending_vm`: Move to DLQ when VM fails during pending checks
- `_clone_vm` rescue: Move to DLQ on clone failure
- `_check_ready_vm`: Move to DLQ when ready VM becomes unreachable
- `_destroy_vm` rescue: Log destroy failures to DLQ

**Acceptance Criteria:**
- [ ] Failed VMs are automatically moved to appropriate DLQ
- [ ] DLQ entries contain complete failure context (error, timestamp, retry count)
- [ ] DLQ entries expire after configurable TTL
- [ ] DLQ size is limited to prevent unbounded growth
- [ ] DLQ entries are queryable via Redis CLI or API

### 2. Auto-Purge Mechanism

#### Purpose
Automatically remove stale entries from queues to prevent resource leaks and improve queue health.

#### Design

**Purge Targets:**
1. **Pending VMs**: Stuck in pending > max_pending_age (e.g., 2 hours)
2. **Ready VMs**: Idle in ready queue > max_ready_age (e.g., 24 hours for on-demand, 48 hours for pool)
3. **Completed VMs**: In completed queue > max_completed_age (e.g., 1 hour)
4. **Orphaned VM Metadata**: VM hash exists but VM not in any queue
5. **Expired Requests**: On-demand requests > max_request_age (e.g., 24 hours)

**Configuration:**
```yaml
:config:
  purge_enabled: true
  purge_interval: 3600  # seconds (1 hour)
  max_pending_age: 7200  # seconds (2 hours)
  max_ready_age: 86400  # seconds (24 hours)
  max_completed_age: 3600  # seconds (1 hour)
  max_orphaned_age: 86400  # seconds (24 hours)
  max_request_age: 86400  # seconds (24 hours)
  purge_dry_run: false  # if true, log what would be purged but don't purge
```

**Purge Process:**
1. Scan each queue for stale entries (based on age thresholds)
2. Check if VM still exists in provider (optional validation)
3. Move stale entries to DLQ with reason
4. Remove from original queue
5. Log purge metrics

**Implementation:**
- New method: `purge_stale_queue_entries` - main purge loop
- Helper methods: `check_pending_age`, `check_ready_age`, `check_completed_age`, `find_orphaned_metadata`
- Scheduled task: Run every `purge_interval` seconds

**Acceptance Criteria:**
- [ ] Stale pending VMs are detected and moved to DLQ
- [ ] Stale ready VMs are detected and moved to completed queue
- [ ] Stale completed VMs are removed from queue
- [ ] Orphaned VM metadata is detected and expired
- [ ] Purge metrics are logged (count, age, reason)
- [ ] Dry-run mode available for testing
- [ ] Purge runs on configurable interval

### 3. Health Checks

#### Purpose
Monitor Redis queue health and expose metrics for alerting and dashboards.

#### Design

**Health Metrics:**
```ruby
{
  queues: {
    pending: {
      pool_name: {
        size: 10,
        oldest_age: 3600,  # seconds
        avg_age: 1200,
        stuck_count: 2  # VMs older than threshold
      }
    },
    ready: { ... },
    completed: { ... },
    dlq: { ... }
  },
  tasks: {
    clone: { active: 5, pending: 10 },
    ondemand: { active: 2, pending: 5 }
  },
  processing_rate: {
    clone_rate: 10.5,  # VMs per minute
    destroy_rate: 8.2
  },
  errors: {
    dlq_size: 150,
    stuck_vm_count: 5,
    orphaned_metadata_count: 12
  },
  status: "healthy|degraded|unhealthy"
}
```

**Health Status Criteria:**
- **Healthy**: All queues within normal thresholds, DLQ size < 100, no stuck VMs
- **Degraded**: Some queues elevated but functional, DLQ size < 1000, few stuck VMs
- **Unhealthy**: Queues critically backed up, DLQ size > 1000, many stuck VMs

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

**Implementation:**
- New method: `check_queue_health` - main health check
- Helper methods: `calculate_queue_metrics`, `calculate_processing_rate`, `determine_health_status`
- Expose via:
  - Redis hash: `vmpooler__health` (for API consumption)
  - Metrics: Push to existing $metrics system
  - Logs: Periodic health summary in logs

**Acceptance Criteria:**
- [ ] Queue sizes are monitored per pool
- [ ] Queue ages are calculated (oldest, average)
- [ ] Stuck VMs are detected (age > threshold)
- [ ] DLQ size is monitored
- [ ] Processing rates are calculated
- [ ] Overall health status is determined
- [ ] Health metrics are exposed via Redis, metrics, and logs
- [ ] Health check runs on configurable interval

## Implementation Plan

### Phase 1: Dead-Letter Queue
1. Add DLQ configuration parsing
2. Implement `move_to_dlq` helper method
3. Update `fail_pending_vm` to use DLQ
4. Update `_clone_vm` rescue block to use DLQ
5. Update `_check_ready_vm` to use DLQ
6. Add DLQ TTL enforcement
7. Add DLQ size limiting
8. Unit tests for DLQ operations

### Phase 2: Auto-Purge
1. Add purge configuration parsing
2. Implement `purge_stale_queue_entries` main loop
3. Implement age-checking helper methods
4. Implement orphan detection
5. Add purge metrics logging
6. Add dry-run mode
7. Unit tests for purge logic
8. Integration test for full purge cycle

### Phase 3: Health Checks
1. Add health check configuration parsing
2. Implement `check_queue_health` main method
3. Implement metric calculation helpers
4. Implement health status determination
5. Expose metrics via Redis hash
6. Expose metrics via $metrics system
7. Add periodic health logging
8. Unit tests for health check logic

### Phase 4: Integration & Documentation
1. Update configuration examples
2. Update operator documentation
3. Update API documentation (if exposing health endpoint)
4. Add troubleshooting guide for DLQ/purge
5. Create runbook for operators
6. Update TESTING.md with DLQ/purge/health check testing

## Migration & Rollout

### Backward Compatibility
- All features are opt-in via configuration
- Default: `dlq_enabled: false`, `purge_enabled: false`, `health_check_enabled: false`
- Existing behavior unchanged when features disabled

### Rollout Strategy
1. Deploy with features disabled
2. Enable DLQ first, monitor for issues
3. Enable health checks, validate metrics
4. Enable auto-purge in dry-run mode, validate detection
5. Enable auto-purge in live mode, monitor impact

### Monitoring During Rollout
- Monitor DLQ growth rate
- Monitor purge counts and reasons
- Monitor health status changes
- Watch for unexpected VM removal
- Check for performance impact (Redis load, memory)

## Testing Strategy

### Unit Tests
- DLQ capture for various error scenarios
- DLQ TTL enforcement
- DLQ size limiting
- Age calculation for purge detection
- Orphan detection logic
- Health metric calculations
- Health status determination

### Integration Tests
- End-to-end VM failure → DLQ flow
- End-to-end purge cycle
- Health check with real queue data
- DLQ + purge interaction (purge should respect DLQ entries)

### Manual Testing
1. Create VM with invalid template → verify DLQ entry
2. Let VM sit in pending too long → verify purge detection
3. Check health endpoint → verify metrics accuracy
4. Run purge in dry-run → verify correct detection without deletion
5. Run purge in live mode → verify stale entries removed

## API Changes (Optional)

If exposing to API:
```
GET /api/v1/queue/health
Returns: Health metrics JSON

GET /api/v1/queue/dlq?queue=pending&limit=50
Returns: DLQ entries for specified queue

POST /api/v1/queue/purge?dry_run=true
Returns: Purge simulation results (admin only)
```

## Metrics

New metrics to add:
```
vmpooler.dlq.pending.size
vmpooler.dlq.clone.size
vmpooler.dlq.ready.size
vmpooler.dlq.tasks.size

vmpooler.purge.pending.count
vmpooler.purge.ready.count
vmpooler.purge.completed.count
vmpooler.purge.orphaned.count

vmpooler.health.status  # 0=healthy, 1=degraded, 2=unhealthy
vmpooler.health.stuck_vms.count
vmpooler.health.queue.#{queue_name}.size
vmpooler.health.queue.#{queue_name}.oldest_age
```

## Configuration Example

```yaml
---
:config:
  # Existing config...
  
  # Dead-Letter Queue
  dlq_enabled: true
  dlq_ttl: 168  # hours (7 days)
  dlq_max_entries: 10000
  
  # Auto-Purge
  purge_enabled: true
  purge_interval: 3600  # seconds (1 hour)
  purge_dry_run: false
  max_pending_age: 7200  # seconds (2 hours)
  max_ready_age: 86400  # seconds (24 hours)
  max_completed_age: 3600  # seconds (1 hour)
  max_orphaned_age: 86400  # seconds (24 hours)
  
  # Health Checks
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

:redis:
  # Existing redis config...
```
