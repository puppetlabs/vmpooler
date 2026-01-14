## [3.8.1](https://github.com/puppetlabs/vmpooler/tree/3.8.1) (2026-01-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/3.7.0...3.8.1)

**Implemented enhancements:**

- \(P4DEVOPS-9434\) Add rate limiting and input validation security enhancements [\#690](https://github.com/puppetlabs/vmpooler/pull/690) ([mahima-singh](https://github.com/mahima-singh))
- \(P4DEVOPS-8570\) Add Phase 2 optimizations: status API caching and improved Redis pipelining [\#689](https://github.com/puppetlabs/vmpooler/pull/689) ([mahima-singh](https://github.com/mahima-singh))
- \(P4DEVOPS-8567\) Add DLQ, auto-purge, and health checks for Redis queues [\#688](https://github.com/puppetlabs/vmpooler/pull/688) ([mahima-singh](https://github.com/mahima-singh))
- Add retry logic for immediate clone failures [\#687](https://github.com/puppetlabs/vmpooler/pull/687) ([mahima-singh](https://github.com/mahima-singh))

**Fixed bugs:**

- \(P4DEVOPS-8567\) Prevent VM allocation for already-deleted request-ids [\#688](https://github.com/puppetlabs/vmpooler/pull/688) ([mahima-singh](https://github.com/mahima-singh))
- Prevent re-queueing requests already marked as failed [\#687](https://github.com/puppetlabs/vmpooler/pull/687) ([mahima-singh](https://github.com/mahima-singh))
