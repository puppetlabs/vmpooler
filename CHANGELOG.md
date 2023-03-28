# Changelog

## [3.0.0](https://github.com/puppetlabs/vmpooler/tree/3.0.0) (2023-03-28)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.5.0...3.0.0)

**Breaking changes:**

- Direct Users to vmpooler-deployment [\#568](https://github.com/puppetlabs/vmpooler/pull/568) ([yachub](https://github.com/yachub))
- \(RE-15124\) Implement DNS Plugins and Remove api v1 and v2 [\#551](https://github.com/puppetlabs/vmpooler/pull/551) ([yachub](https://github.com/yachub))

## [2.5.0](https://github.com/puppetlabs/vmpooler/tree/2.5.0) (2023-03-06)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.4.0...2.5.0)

**Implemented enhancements:**

- \(RE-15161\) Use timeout builtin to TCPSocket when opening sockets. [\#555](https://github.com/puppetlabs/vmpooler/pull/555) ([isaac-hammes](https://github.com/isaac-hammes))

**Merged pull requests:**

- Add docs and update actions [\#550](https://github.com/puppetlabs/vmpooler/pull/550) ([yachub](https://github.com/yachub))
- \(RE-15111\) Migrate Snyk to Mend Scanning [\#546](https://github.com/puppetlabs/vmpooler/pull/546) ([yachub](https://github.com/yachub))
- \(RE-14811\) Remove DIO as codeowners [\#517](https://github.com/puppetlabs/vmpooler/pull/517) ([yachub](https://github.com/yachub))
- Add Snyk action and Move to RE org [\#511](https://github.com/puppetlabs/vmpooler/pull/511) ([yachub](https://github.com/yachub))
- Add release-engineering to codeowners [\#508](https://github.com/puppetlabs/vmpooler/pull/508) ([yachub](https://github.com/yachub))
- Update docker/Gemfile.lock [\#503](https://github.com/puppetlabs/vmpooler/pull/503) ([yachub](https://github.com/yachub))

## [2.4.0](https://github.com/puppetlabs/vmpooler/tree/2.4.0) (2022-07-25)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.3.0...2.4.0)

**Merged pull requests:**

- \(maint\) Bump version to 2.4.0 [\#502](https://github.com/puppetlabs/vmpooler/pull/502) ([sbeaulie](https://github.com/sbeaulie))
- \(bug\) Prevent failing VMs to be retried infinitely \(ondemand\) [\#501](https://github.com/puppetlabs/vmpooler/pull/501) ([sbeaulie](https://github.com/sbeaulie))
- \(DIO-3138\) vmpooler v2 api missing vm/hostname [\#500](https://github.com/puppetlabs/vmpooler/pull/500) ([sbeaulie](https://github.com/sbeaulie))
- Update rubocop requirement from ~\> 1.1.0 to ~\> 1.28.2 [\#499](https://github.com/puppetlabs/vmpooler/pull/499) ([dependabot[bot]](https://github.com/apps/dependabot))
- Bump mock\_redis from 0.30.0 to 0.31.0 [\#496](https://github.com/puppetlabs/vmpooler/pull/496) ([dependabot[bot]](https://github.com/apps/dependabot))
- Update opentelemetry-instrumentation-redis requirement from = 0.21.2 to = 0.21.3 [\#494](https://github.com/puppetlabs/vmpooler/pull/494) ([dependabot[bot]](https://github.com/apps/dependabot))
- Bump puma from 5.5.2 to 5.6.4 [\#490](https://github.com/puppetlabs/vmpooler/pull/490) ([dependabot[bot]](https://github.com/apps/dependabot))
- Update opentelemetry-instrumentation-http\_client requirement from = 0.19.3 to = 0.19.4 [\#478](https://github.com/puppetlabs/vmpooler/pull/478) ([dependabot[bot]](https://github.com/apps/dependabot))

## [2.3.0](https://github.com/puppetlabs/vmpooler/tree/2.3.0) (2022-04-07)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.2.0...2.3.0)

**Merged pull requests:**

- \(maint\) Fix deprecation warning for redis ruby library [\#489](https://github.com/puppetlabs/vmpooler/pull/489) ([sbeaulie](https://github.com/sbeaulie))
- Add OTel HttpClient Instrumentation [\#477](https://github.com/puppetlabs/vmpooler/pull/477) ([genebean](https://github.com/genebean))
- \(DIO-2833\) Update dev tooling and related docs [\#476](https://github.com/puppetlabs/vmpooler/pull/476) ([genebean](https://github.com/genebean))
- \(DIO-2833\) Connect domain settings to pools, create v2 API [\#475](https://github.com/puppetlabs/vmpooler/pull/475) ([genebean](https://github.com/genebean))

## [2.2.0](https://github.com/puppetlabs/vmpooler/tree/2.2.0) (2021-12-30)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.1.0...2.2.0)

**Merged pull requests:**

- Bump version to 2.2.0 [\#473](https://github.com/puppetlabs/vmpooler/pull/473) ([sbeaulie](https://github.com/sbeaulie))
- \(maint\) Fix EXTRA\_CONFIG merge behavior [\#472](https://github.com/puppetlabs/vmpooler/pull/472) ([sbeaulie](https://github.com/sbeaulie))
- Update to latest OTel gems [\#471](https://github.com/puppetlabs/vmpooler/pull/471) ([genebean](https://github.com/genebean))
- Add additional data to spans in api/v1.rb [\#400](https://github.com/puppetlabs/vmpooler/pull/400) ([genebean](https://github.com/genebean))

## [2.1.0](https://github.com/puppetlabs/vmpooler/tree/2.1.0) (2021-12-13)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/2.0.0...2.1.0)

**Merged pull requests:**

- Ensure all configured providers are loaded [\#470](https://github.com/puppetlabs/vmpooler/pull/470) ([genebean](https://github.com/genebean))
- \(maint\) Adding a provider method tag\_vm\_user [\#469](https://github.com/puppetlabs/vmpooler/pull/469) ([sbeaulie](https://github.com/sbeaulie))
- Update testing.yml [\#468](https://github.com/puppetlabs/vmpooler/pull/468) ([sbeaulie](https://github.com/sbeaulie))
- Move vsphere specific methods out of vmpooler [\#467](https://github.com/puppetlabs/vmpooler/pull/467) ([sbeaulie](https://github.com/sbeaulie))

## [2.0.0](https://github.com/puppetlabs/vmpooler/tree/2.0.0) (2021-12-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.3.0...2.0.0)

**Merged pull requests:**

- Use credentials file for Rubygems auth [\#466](https://github.com/puppetlabs/vmpooler/pull/466) ([genebean](https://github.com/genebean))
- Release prep for v2.0.0 [\#465](https://github.com/puppetlabs/vmpooler/pull/465) ([genebean](https://github.com/genebean))
- Add Gem release workflow [\#464](https://github.com/puppetlabs/vmpooler/pull/464) ([genebean](https://github.com/genebean))
- Update icon in the readme to reference this repo [\#463](https://github.com/puppetlabs/vmpooler/pull/463) ([genebean](https://github.com/genebean))
- \(DIO-2769\) Move vsphere provider to its own gem [\#462](https://github.com/puppetlabs/vmpooler/pull/462) ([genebean](https://github.com/genebean))

## [1.3.0](https://github.com/puppetlabs/vmpooler/tree/1.3.0) (2021-11-15)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.2.0...1.3.0)

**Merged pull requests:**

- \(DIO-2675\) Undo pool size & template overrides [\#461](https://github.com/puppetlabs/vmpooler/pull/461) ([genebean](https://github.com/genebean))
- \(DIO-2186\) Token migration [\#460](https://github.com/puppetlabs/vmpooler/pull/460) ([genebean](https://github.com/genebean))

## [1.2.0](https://github.com/puppetlabs/vmpooler/tree/1.2.0) (2021-09-15)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.1.2...1.2.0)

**Merged pull requests:**

- \(DIO-2621\) Make LDAP encryption configurable [\#459](https://github.com/puppetlabs/vmpooler/pull/459) ([genebean](https://github.com/genebean))

## [1.1.2](https://github.com/puppetlabs/vmpooler/tree/1.1.2) (2021-08-25)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.1.1...1.1.2)

**Merged pull requests:**

- \(DIO-541\) Fix jenkins and user usage metrics [\#458](https://github.com/puppetlabs/vmpooler/pull/458) ([yachub](https://github.com/yachub))

## [1.1.1](https://github.com/puppetlabs/vmpooler/tree/1.1.1) (2021-08-24)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.1.0...1.1.1)

**Merged pull requests:**

- \(POOLER-198\) Fix otel warning: Bump otel gems to 0.17.0 [\#457](https://github.com/puppetlabs/vmpooler/pull/457) ([yachub](https://github.com/yachub))

## [1.1.0](https://github.com/puppetlabs/vmpooler/tree/1.1.0) (2021-08-18)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.1.0-rc.1...1.1.0)

**Merged pull requests:**

- \(POOLER-176\) Add Operation Label to User Metric [\#455](https://github.com/puppetlabs/vmpooler/pull/455) ([yachub](https://github.com/yachub))
- Update OTel gems to 0.15.0 [\#450](https://github.com/puppetlabs/vmpooler/pull/450) ([genebean](https://github.com/genebean))
- Migrate testing to GH Actions from Travis [\#446](https://github.com/puppetlabs/vmpooler/pull/446) ([genebean](https://github.com/genebean))

## [1.1.0-rc.1](https://github.com/puppetlabs/vmpooler/tree/1.1.0-rc.1) (2021-08-11)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/1.0.0...1.1.0-rc.1)

## [1.0.0](https://github.com/puppetlabs/vmpooler/tree/1.0.0) (2021-02-02)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.18.2...1.0.0)

**Merged pull requests:**

- Update OTel gems to 0.13.z [\#447](https://github.com/puppetlabs/vmpooler/pull/447) ([genebean](https://github.com/genebean))
- \(DIO-1503\) Fix regex for ondemand instances [\#445](https://github.com/puppetlabs/vmpooler/pull/445) ([genebean](https://github.com/genebean))
- \(maint\) Update lightstep pre-deploy ghaction to v0.2.6 [\#440](https://github.com/puppetlabs/vmpooler/pull/440) ([rooneyshuman](https://github.com/rooneyshuman))

## [0.18.2](https://github.com/puppetlabs/vmpooler/tree/0.18.2) (2020-11-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.18.1...0.18.2)

**Merged pull requests:**

- Remove usage of redis multi from api [\#438](https://github.com/puppetlabs/vmpooler/pull/438) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Fix checkout counter allocation [\#437](https://github.com/puppetlabs/vmpooler/pull/437) ([jcoconnor](https://github.com/jcoconnor))

## [0.18.1](https://github.com/puppetlabs/vmpooler/tree/0.18.1) (2020-11-10)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.18.0...0.18.1)

**Merged pull requests:**

- Update Puma to 5.0.4 from ~4.3 [\#436](https://github.com/puppetlabs/vmpooler/pull/436) ([genebean](https://github.com/genebean))
- \(MAINT\) Fix checkout counter allocation [\#435](https://github.com/puppetlabs/vmpooler/pull/435) ([jcoconnor](https://github.com/jcoconnor))
- \(POOLER-193\) Mark checked out VM as active [\#434](https://github.com/puppetlabs/vmpooler/pull/434) ([mattkirby](https://github.com/mattkirby))
- Update to OTel 0.8.0 [\#432](https://github.com/puppetlabs/vmpooler/pull/432) ([genebean](https://github.com/genebean))
- \(POOLER-192\) Use Rubocop 1.0 [\#423](https://github.com/puppetlabs/vmpooler/pull/423) ([rooneyshuman](https://github.com/rooneyshuman))

## [0.18.0](https://github.com/puppetlabs/vmpooler/tree/0.18.0) (2020-10-26)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.17.0...0.18.0)

**Merged pull requests:**

- \(maint\) Speedup the tagging method [\#422](https://github.com/puppetlabs/vmpooler/pull/422) ([sbeaulie](https://github.com/sbeaulie))
- \(DIO-1065\) Add lightstep gh action [\#421](https://github.com/puppetlabs/vmpooler/pull/421) ([rooneyshuman](https://github.com/rooneyshuman))

## [0.17.0](https://github.com/puppetlabs/vmpooler/tree/0.17.0) (2020-10-20)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.16.3...0.17.0)

**Merged pull requests:**

- \(DIO-1059\) Optionally add snapshot tuning params at clone time [\#419](https://github.com/puppetlabs/vmpooler/pull/419) ([suckatrash](https://github.com/suckatrash))

## [0.16.3](https://github.com/puppetlabs/vmpooler/tree/0.16.3) (2020-10-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.16.2...0.16.3)

**Merged pull requests:**

- \(POOLER-191\) Add checking for running instances that are not in active [\#418](https://github.com/puppetlabs/vmpooler/pull/418) ([mattkirby](https://github.com/mattkirby))

## [0.16.2](https://github.com/puppetlabs/vmpooler/tree/0.16.2) (2020-10-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.16.1...0.16.2)

**Merged pull requests:**

- Bump OTel Sinatra to 0.7.1 [\#417](https://github.com/puppetlabs/vmpooler/pull/417) ([genebean](https://github.com/genebean))

## [0.16.1](https://github.com/puppetlabs/vmpooler/tree/0.16.1) (2020-10-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.16.0...0.16.1)

## [0.16.0](https://github.com/puppetlabs/vmpooler/tree/0.16.0) (2020-10-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.15.0...0.16.0)

**Merged pull requests:**

- Update to OTel 0.7.0 [\#416](https://github.com/puppetlabs/vmpooler/pull/416) ([genebean](https://github.com/genebean))

## [0.15.0](https://github.com/puppetlabs/vmpooler/tree/0.15.0) (2020-09-30)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.9...0.15.0)

**Merged pull requests:**

- \(maint\) Centralize dependency management in the gemspec [\#407](https://github.com/puppetlabs/vmpooler/pull/407) ([sbeaulie](https://github.com/sbeaulie))
- \(pooler-180\) Add healthcheck endpoint, spec testing [\#406](https://github.com/puppetlabs/vmpooler/pull/406) ([suckatrash](https://github.com/suckatrash))

## [0.14.9](https://github.com/puppetlabs/vmpooler/tree/0.14.9) (2020-09-21)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.8...0.14.9)

**Merged pull requests:**

- Adding make to the other two Dockerfiles [\#405](https://github.com/puppetlabs/vmpooler/pull/405) ([genebean](https://github.com/genebean))

## [0.14.8](https://github.com/puppetlabs/vmpooler/tree/0.14.8) (2020-09-18)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.7...0.14.8)

**Merged pull requests:**

- Fix mixup of gem placement. [\#404](https://github.com/puppetlabs/vmpooler/pull/404) ([genebean](https://github.com/genebean))

## [0.14.7](https://github.com/puppetlabs/vmpooler/tree/0.14.7) (2020-09-18)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.6...0.14.7)

**Merged pull requests:**

- Add OTel resource detectors [\#401](https://github.com/puppetlabs/vmpooler/pull/401) ([genebean](https://github.com/genebean))
- Add distributed tracing [\#399](https://github.com/puppetlabs/vmpooler/pull/399) ([genebean](https://github.com/genebean))

## [0.14.6](https://github.com/puppetlabs/vmpooler/tree/0.14.6) (2020-09-17)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.5...0.14.6)

**Merged pull requests:**

- \(POOLER-184\) Pool manager retry and exit on failure [\#398](https://github.com/puppetlabs/vmpooler/pull/398) ([sbeaulie](https://github.com/sbeaulie))
- \(maint\) Add promstats component check [\#397](https://github.com/puppetlabs/vmpooler/pull/397) ([rooneyshuman](https://github.com/rooneyshuman))
- Test vmpooler on latest 2.5 [\#393](https://github.com/puppetlabs/vmpooler/pull/393) ([mattkirby](https://github.com/mattkirby))
- Update rbvmomi requirement from ~\> 2.1 to \>= 2.1, \< 4.0 [\#391](https://github.com/puppetlabs/vmpooler/pull/391) ([dependabot[bot]](https://github.com/apps/dependabot))

## [0.14.5](https://github.com/puppetlabs/vmpooler/tree/0.14.5) (2020-08-21)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.4...0.14.5)

**Merged pull requests:**

- \(MAINT\) Fix Staledns error counter [\#396](https://github.com/puppetlabs/vmpooler/pull/396) ([jcoconnor](https://github.com/jcoconnor))

## [0.14.4](https://github.com/puppetlabs/vmpooler/tree/0.14.4) (2020-08-21)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.3...0.14.4)

**Merged pull requests:**

- \(MAINT\) Normalise all tokens for stats [\#395](https://github.com/puppetlabs/vmpooler/pull/395) ([jcoconnor](https://github.com/jcoconnor))

## [0.14.3](https://github.com/puppetlabs/vmpooler/tree/0.14.3) (2020-08-06)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.2...0.14.3)

**Merged pull requests:**

- \(POOLER-186\) Fix template alias evaluation with backend weight of 0 [\#394](https://github.com/puppetlabs/vmpooler/pull/394) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Clarity refactor of Prom Stats code [\#390](https://github.com/puppetlabs/vmpooler/pull/390) ([jcoconnor](https://github.com/jcoconnor))

## [0.14.2](https://github.com/puppetlabs/vmpooler/tree/0.14.2) (2020-08-03)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.1...0.14.2)

**Merged pull requests:**

- Ensure lifetime is set when creating ondemand instances [\#392](https://github.com/puppetlabs/vmpooler/pull/392) ([mattkirby](https://github.com/mattkirby))
- Fix vmpooler folder purging [\#389](https://github.com/puppetlabs/vmpooler/pull/389) ([mattkirby](https://github.com/mattkirby))

## [0.14.1](https://github.com/puppetlabs/vmpooler/tree/0.14.1) (2020-07-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.14.0...0.14.1)

**Merged pull requests:**

- Correctly handle multiple pools of same alias in ondemand checkout [\#388](https://github.com/puppetlabs/vmpooler/pull/388) ([mattkirby](https://github.com/mattkirby))
- Update travis config to remove deprecated style [\#387](https://github.com/puppetlabs/vmpooler/pull/387) ([rooneyshuman](https://github.com/rooneyshuman))
- Update Dependabot config file [\#386](https://github.com/puppetlabs/vmpooler/pull/386) ([dependabot-preview[bot]](https://github.com/apps/dependabot-preview))

## [0.14.0](https://github.com/puppetlabs/vmpooler/tree/0.14.0) (2020-07-01)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.13.3...0.14.0)

**Merged pull requests:**

- Add a note on jruby 9.2.11 and redis connection pooling changes [\#384](https://github.com/puppetlabs/vmpooler/pull/384) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-167\) Allow for network configuration at vm clone time [\#382](https://github.com/puppetlabs/vmpooler/pull/382) ([rooneyshuman](https://github.com/rooneyshuman))
- \(POOLER-160\) Add Prometheus Metrics to vmpooler [\#372](https://github.com/puppetlabs/vmpooler/pull/372) ([jcoconnor](https://github.com/jcoconnor))

## [0.13.3](https://github.com/puppetlabs/vmpooler/tree/0.13.3) (2020-06-15)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.13.2...0.13.3)

**Merged pull requests:**

- \(POOLER-174\) Reduce duplicate of on demand code introduced in POOLER-158 [\#383](https://github.com/puppetlabs/vmpooler/pull/383) ([sbeaulie](https://github.com/sbeaulie))

## [0.13.2](https://github.com/puppetlabs/vmpooler/tree/0.13.2) (2020-06-05)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.13.1...0.13.2)

**Merged pull requests:**

- Rescue and warn when graphite connection cannot be opened [\#379](https://github.com/puppetlabs/vmpooler/pull/379) ([mattkirby](https://github.com/mattkirby))

## [0.13.1](https://github.com/puppetlabs/vmpooler/tree/0.13.1) (2020-06-04)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.13.0...0.13.1)

**Merged pull requests:**

- \(maint\) Fix merge issue [\#378](https://github.com/puppetlabs/vmpooler/pull/378) ([sbeaulie](https://github.com/sbeaulie))

## [0.13.0](https://github.com/puppetlabs/vmpooler/tree/0.13.0) (2020-06-04)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.12.0...0.13.0)

**Merged pull requests:**

- \(POOLER-166\) Check for stale dns records [\#377](https://github.com/puppetlabs/vmpooler/pull/377) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-158\) Add support for ondemand provisioning [\#375](https://github.com/puppetlabs/vmpooler/pull/375) ([mattkirby](https://github.com/mattkirby))

## [0.12.0](https://github.com/puppetlabs/vmpooler/tree/0.12.0) (2020-05-28)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.11.3...0.12.0)

**Merged pull requests:**

- \(POOLER-171\) Enable support for multiple user objects [\#376](https://github.com/puppetlabs/vmpooler/pull/376) ([rooneyshuman](https://github.com/rooneyshuman))

## [0.11.3](https://github.com/puppetlabs/vmpooler/tree/0.11.3) (2020-04-29)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.11.2...0.11.3)

**Merged pull requests:**

- \(DIO-608\) vmpooler SUT handed out multiple times [\#374](https://github.com/puppetlabs/vmpooler/pull/374) ([sbeaulie](https://github.com/sbeaulie))
- \(MAINT\) Update CODEOWNERS [\#373](https://github.com/puppetlabs/vmpooler/pull/373) ([jcoconnor](https://github.com/jcoconnor))

## [0.11.2](https://github.com/puppetlabs/vmpooler/tree/0.11.2) (2020-04-16)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.11.1...0.11.2)

**Merged pull requests:**

- \(POOLER-161\) Fix extending vm lifetime when max lifetime is set [\#371](https://github.com/puppetlabs/vmpooler/pull/371) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-165\) Fix purge\_unconfigured\_folders [\#370](https://github.com/puppetlabs/vmpooler/pull/370) ([mattkirby](https://github.com/mattkirby))
- Update rake requirement from ~\> 12.3 to \>= 12.3, \< 14.0 [\#369](https://github.com/puppetlabs/vmpooler/pull/369) ([dependabot-preview[bot]](https://github.com/apps/dependabot-preview))

## [0.11.1](https://github.com/puppetlabs/vmpooler/tree/0.11.1) (2020-03-17)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.11.0...0.11.1)

**Merged pull requests:**

- Remove providers addition to docker-compose.yml [\#368](https://github.com/puppetlabs/vmpooler/pull/368) ([mattkirby](https://github.com/mattkirby))
- Add Dependabot to keep gems updated [\#367](https://github.com/puppetlabs/vmpooler/pull/367) ([genebean](https://github.com/genebean))
- Update gem dependencies to latest versions [\#366](https://github.com/puppetlabs/vmpooler/pull/366) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-156\) Detect redis connection failures [\#365](https://github.com/puppetlabs/vmpooler/pull/365) ([mattkirby](https://github.com/mattkirby))
- Add a .dockerignore file [\#363](https://github.com/puppetlabs/vmpooler/pull/363) ([mattkirby](https://github.com/mattkirby))

## [0.11.0](https://github.com/puppetlabs/vmpooler/tree/0.11.0) (2020-03-11)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.10.3...0.11.0)

**Merged pull requests:**

- Pin to JRuby 9.2.9 in Dockerfiles [\#362](https://github.com/puppetlabs/vmpooler/pull/362) ([highb](https://github.com/highb))
- Manual Rubocop Fixes [\#361](https://github.com/puppetlabs/vmpooler/pull/361) ([highb](https://github.com/highb))
- "Unsafe" rubocop fixes [\#360](https://github.com/puppetlabs/vmpooler/pull/360) ([highb](https://github.com/highb))
- Fix Rubocop "safe" auto-corrections [\#359](https://github.com/puppetlabs/vmpooler/pull/359) ([highb](https://github.com/highb))
- Remove duplicate of 0.10.2 from CHANGELOG [\#358](https://github.com/puppetlabs/vmpooler/pull/358) ([highb](https://github.com/highb))
- \(POOLER-157\) Add extra\_config option to vmpooler [\#357](https://github.com/puppetlabs/vmpooler/pull/357) ([mattkirby](https://github.com/mattkirby))

## [0.10.3](https://github.com/puppetlabs/vmpooler/tree/0.10.3) (2020-03-04)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.10.2...0.10.3)

**Merged pull requests:**

- Release 0.10.3 [\#356](https://github.com/puppetlabs/vmpooler/pull/356) ([highb](https://github.com/highb))
- \(POOLER-154\) Delay vm host update until after migration completes [\#355](https://github.com/puppetlabs/vmpooler/pull/355) ([highb](https://github.com/highb))

## [0.10.2](https://github.com/puppetlabs/vmpooler/tree/0.10.2) (2020-02-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.10.1...0.10.2)

## [0.10.1](https://github.com/puppetlabs/vmpooler/tree/0.10.1) (2020-02-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.10.0...0.10.1)

## [0.10.0](https://github.com/puppetlabs/vmpooler/tree/0.10.0) (2020-02-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.9.1...0.10.0)

**Merged pull requests:**

- Update changelog for 0.10.0 release [\#354](https://github.com/puppetlabs/vmpooler/pull/354) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-153\) Add endpoint for resetting a pool [\#353](https://github.com/puppetlabs/vmpooler/pull/353) ([mattkirby](https://github.com/mattkirby))

## [0.9.1](https://github.com/puppetlabs/vmpooler/tree/0.9.1) (2020-01-28)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.9.0...0.9.1)

**Merged pull requests:**

- Generate a wider set of legal names [\#351](https://github.com/puppetlabs/vmpooler/pull/351) ([nicklewis](https://github.com/nicklewis))

## [0.9.0](https://github.com/puppetlabs/vmpooler/tree/0.9.0) (2019-12-12)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.8.2...0.9.0)

**Closed issues:**

- find\_cluster in vsphere\_helper doesn't support host folders [\#205](https://github.com/puppetlabs/vmpooler/issues/205)

**Merged pull requests:**

- \(QENG-7531\) Add Marked as Failed Stat [\#350](https://github.com/puppetlabs/vmpooler/pull/350) ([jcoconnor](https://github.com/jcoconnor))
- \(POOLER-123\) Implement a max TTL [\#349](https://github.com/puppetlabs/vmpooler/pull/349) ([sbeaulie](https://github.com/sbeaulie))
- Support nested host folders in find\_cluster\(\) [\#348](https://github.com/puppetlabs/vmpooler/pull/348) ([seanmil](https://github.com/seanmil))
- Update CHANGELOG for 0.8.2 [\#347](https://github.com/puppetlabs/vmpooler/pull/347) ([highb](https://github.com/highb))

## [0.8.2](https://github.com/puppetlabs/vmpooler/tree/0.8.2) (2019-11-06)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.8.1...0.8.2)

**Merged pull requests:**

- Update rubocop configs [\#346](https://github.com/puppetlabs/vmpooler/pull/346) ([highb](https://github.com/highb))
- \(QENG-7530\) Add check for unique hostnames [\#345](https://github.com/puppetlabs/vmpooler/pull/345) ([highb](https://github.com/highb))
- \(QENG-7530\) Fix hostname\_shorten regex [\#344](https://github.com/puppetlabs/vmpooler/pull/344) ([highb](https://github.com/highb))
- Update changelog for 0.8.1 release [\#343](https://github.com/puppetlabs/vmpooler/pull/343) ([mattkirby](https://github.com/mattkirby))

## [0.8.1](https://github.com/puppetlabs/vmpooler/tree/0.8.1) (2019-10-25)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.8.0...0.8.1)

**Merged pull requests:**

- Add spicy-proton to vmpooler.gemspec [\#342](https://github.com/puppetlabs/vmpooler/pull/342) ([mattkirby](https://github.com/mattkirby))

## [0.8.0](https://github.com/puppetlabs/vmpooler/tree/0.8.0) (2019-10-25)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.7.2...0.8.0)

**Merged pull requests:**

- \(QENG-7530\) Make VM names more human readable [\#341](https://github.com/puppetlabs/vmpooler/pull/341) ([highb](https://github.com/highb))

## [0.7.2](https://github.com/puppetlabs/vmpooler/tree/0.7.2) (2019-10-24)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.7.1...0.7.2)

**Merged pull requests:**

- Simplify declaration of checkoutlock mutex [\#340](https://github.com/puppetlabs/vmpooler/pull/340) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-150\) Synchronize checkout operations for API [\#339](https://github.com/puppetlabs/vmpooler/pull/339) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-148\) Fix undefined variable bug in \_check\_ready\_vm. [\#338](https://github.com/puppetlabs/vmpooler/pull/338) ([quorten](https://github.com/quorten))
- Add CODEOWNERS file to vmpooler [\#337](https://github.com/puppetlabs/vmpooler/pull/337) ([mattkirby](https://github.com/mattkirby))

## [0.7.1](https://github.com/puppetlabs/vmpooler/tree/0.7.1) (2019-08-26)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.7.0...0.7.1)

**Merged pull requests:**

- \(POOLER-147\) Fix create\_linked\_clone pool option [\#336](https://github.com/puppetlabs/vmpooler/pull/336) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Update changelog for 0.7.0 release [\#335](https://github.com/puppetlabs/vmpooler/pull/335) ([mattkirby](https://github.com/mattkirby))

## [0.7.0](https://github.com/puppetlabs/vmpooler/tree/0.7.0) (2019-08-21)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.6.3...0.7.0)

**Merged pull requests:**

- \(POOLER-142\) Add running host to vm API data [\#334](https://github.com/puppetlabs/vmpooler/pull/334) ([mattkirby](https://github.com/mattkirby))
- Make it possible to disable linked clones [\#333](https://github.com/puppetlabs/vmpooler/pull/333) ([mattkirby](https://github.com/mattkirby))

## [0.6.3](https://github.com/puppetlabs/vmpooler/tree/0.6.3) (2019-07-29)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.6.2...0.6.3)

**Closed issues:**

- Named snapshots? [\#140](https://github.com/puppetlabs/vmpooler/issues/140)

**Merged pull requests:**

- \(POOLER-143\) Add clone\_target config change to API [\#332](https://github.com/puppetlabs/vmpooler/pull/332) ([smcelmurry](https://github.com/smcelmurry))
- \(MAINT\) Update changelog for 0.6.2 [\#331](https://github.com/puppetlabs/vmpooler/pull/331) ([mattkirby](https://github.com/mattkirby))

## [0.6.2](https://github.com/puppetlabs/vmpooler/tree/0.6.2) (2019-07-17)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.6.1...0.6.2)

**Merged pull requests:**

- \(POOLER-140\) Fix typo in domain [\#330](https://github.com/puppetlabs/vmpooler/pull/330) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-140\) Ensure a VM is alive at checkout [\#329](https://github.com/puppetlabs/vmpooler/pull/329) ([mattkirby](https://github.com/mattkirby))

## [0.6.1](https://github.com/puppetlabs/vmpooler/tree/0.6.1) (2019-05-08)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.6.0...0.6.1)

**Merged pull requests:**

- Update Changelog ahead of building 0.6.1 [\#328](https://github.com/puppetlabs/vmpooler/pull/328) ([sbeaulie](https://github.com/sbeaulie))
- Update API.md \[skip ci\] [\#327](https://github.com/puppetlabs/vmpooler/pull/327) ([sbeaulie](https://github.com/sbeaulie))
- \(maint\) Optimize the status api using redis pipeline [\#326](https://github.com/puppetlabs/vmpooler/pull/326) ([sbeaulie](https://github.com/sbeaulie))
- Update changelog ahead of 0.6.0 release. [\#325](https://github.com/puppetlabs/vmpooler/pull/325) ([mattkirby](https://github.com/mattkirby))

## [0.6.0](https://github.com/puppetlabs/vmpooler/tree/0.6.0) (2019-04-24)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.5.1...0.6.0)

**Merged pull requests:**

- \(QENG-7201\) Vmpooler pool statistic endpoint optimization [\#324](https://github.com/puppetlabs/vmpooler/pull/324) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-141\) Fix order of processing migrating and pending queues [\#323](https://github.com/puppetlabs/vmpooler/pull/323) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Add bundler to dockerfile\_local [\#322](https://github.com/puppetlabs/vmpooler/pull/322) ([mattkirby](https://github.com/mattkirby))
- Update changelog to 0.5.1 [\#321](https://github.com/puppetlabs/vmpooler/pull/321) ([mattkirby](https://github.com/mattkirby))

## [0.5.1](https://github.com/puppetlabs/vmpooler/tree/0.5.1) (2019-04-11)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.5.0...0.5.1)

**Merged pull requests:**

- \(POOLER-140\) Ensure a running VM stays in a queue [\#320](https://github.com/puppetlabs/vmpooler/pull/320) ([mattkirby](https://github.com/mattkirby))
- Fix Dockerfile link in readme and add note about http requests for dev [\#316](https://github.com/puppetlabs/vmpooler/pull/316) ([briancain](https://github.com/briancain))

## [0.5.0](https://github.com/puppetlabs/vmpooler/tree/0.5.0) (2019-02-14)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.4.0...0.5.0)

**Merged pull requests:**

- \(POOLER-139\) Fix discovering checked out VM [\#318](https://github.com/puppetlabs/vmpooler/pull/318) ([mattkirby](https://github.com/mattkirby))

## [0.4.0](https://github.com/puppetlabs/vmpooler/tree/0.4.0) (2019-02-06)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.3.0...0.4.0)

**Merged pull requests:**

- \(MAINT\) Update changelog for 0.4.0 release [\#315](https://github.com/puppetlabs/vmpooler/pull/315) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-138\) Support multiple pools per alias [\#314](https://github.com/puppetlabs/vmpooler/pull/314) ([mattkirby](https://github.com/mattkirby))
- Update dockerfile jruby to 9.2 [\#313](https://github.com/puppetlabs/vmpooler/pull/313) ([mattkirby](https://github.com/mattkirby))
- Stop testing ruby 2.3.x [\#312](https://github.com/puppetlabs/vmpooler/pull/312) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-137\) Support integer environment variables [\#311](https://github.com/puppetlabs/vmpooler/pull/311) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Update travis to test latest ruby [\#309](https://github.com/puppetlabs/vmpooler/pull/309) ([mattkirby](https://github.com/mattkirby))

## [0.3.0](https://github.com/puppetlabs/vmpooler/tree/0.3.0) (2018-12-20)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.2.2...0.3.0)

**Merged pull requests:**

- Change version 0.2.2 to 0.3.0 [\#310](https://github.com/puppetlabs/vmpooler/pull/310) ([mattkirby](https://github.com/mattkirby))
- Ensure nodes are consistent for usage stats [\#308](https://github.com/puppetlabs/vmpooler/pull/308) ([mattkirby](https://github.com/mattkirby))
- Update changelog for 0.2.3 [\#307](https://github.com/puppetlabs/vmpooler/pull/307) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-134\) Ship VM usage stats [\#306](https://github.com/puppetlabs/vmpooler/pull/306) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-133\) Identify when a ready VM has failed [\#305](https://github.com/puppetlabs/vmpooler/pull/305) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-37\) Document HTTP responses [\#304](https://github.com/puppetlabs/vmpooler/pull/304) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-132\) Sync pool size on dashboard start [\#303](https://github.com/puppetlabs/vmpooler/pull/303) ([mattkirby](https://github.com/mattkirby))

## [0.2.2](https://github.com/puppetlabs/vmpooler/tree/0.2.2) (2018-10-01)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.2.1...0.2.2)

**Merged pull requests:**

- Update changelog version in preparation for release [\#302](https://github.com/puppetlabs/vmpooler/pull/302) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-131\) Return requested name when getting VMs [\#301](https://github.com/puppetlabs/vmpooler/pull/301) ([mattkirby](https://github.com/mattkirby))
- Add docker-compose and dockerfile to support it [\#300](https://github.com/puppetlabs/vmpooler/pull/300) ([mattkirby](https://github.com/mattkirby))

## [0.2.1](https://github.com/puppetlabs/vmpooler/tree/0.2.1) (2018-09-19)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.2.0...0.2.1)

**Merged pull requests:**

- Bump version for vmpooler in changelog [\#299](https://github.com/puppetlabs/vmpooler/pull/299) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-129\) Allow setting weights for backends [\#298](https://github.com/puppetlabs/vmpooler/pull/298) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-130\) Improve delta disk creation handling [\#297](https://github.com/puppetlabs/vmpooler/pull/297) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-114\) Refactor check\_pool in pool\_manager [\#296](https://github.com/puppetlabs/vmpooler/pull/296) ([mattkirby](https://github.com/mattkirby))

## [0.2.0](https://github.com/puppetlabs/vmpooler/tree/0.2.0) (2018-07-25)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/0.1.0...0.2.0)

**Closed issues:**

- create release [\#262](https://github.com/puppetlabs/vmpooler/issues/262)
- Add API to delete a snapshot [\#163](https://github.com/puppetlabs/vmpooler/issues/163)

**Merged pull requests:**

- \(MAINT\) release 0.2.0 [\#294](https://github.com/puppetlabs/vmpooler/pull/294) ([mattkirby](https://github.com/mattkirby))
- Remove VM from completed only after destroy [\#293](https://github.com/puppetlabs/vmpooler/pull/293) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-128\) Remove references to VM mutex when destroying [\#292](https://github.com/puppetlabs/vmpooler/pull/292) ([mattkirby](https://github.com/mattkirby))
- \(doc\) Document config via environment [\#291](https://github.com/puppetlabs/vmpooler/pull/291) ([mattkirby](https://github.com/mattkirby))
- \(maint\) change domain to example.com [\#290](https://github.com/puppetlabs/vmpooler/pull/290) ([steveax](https://github.com/steveax))
- Update entrypoint in dockerfile for vmpooler gem [\#289](https://github.com/puppetlabs/vmpooler/pull/289) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) release 0.1.0 [\#288](https://github.com/puppetlabs/vmpooler/pull/288) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-66\) Purge vms and folders no longer configured [\#274](https://github.com/puppetlabs/vmpooler/pull/274) ([mattkirby](https://github.com/mattkirby))
- Adds a new mechanism to load providers from any gem or file path automatically [\#263](https://github.com/puppetlabs/vmpooler/pull/263) ([logicminds](https://github.com/logicminds))

## [0.1.0](https://github.com/puppetlabs/vmpooler/tree/0.1.0) (2018-07-17)

[Full Changelog](https://github.com/puppetlabs/vmpooler/compare/4c858d012a262093383e57ea6db790521886d8d4...0.1.0)

**Closed issues:**

- jruby 1.7.8 does not support safe\_load [\#243](https://github.com/puppetlabs/vmpooler/issues/243)
- YAML.safe\_load does not work with symbols in config file [\#240](https://github.com/puppetlabs/vmpooler/issues/240)
- vmpooler fails to fetch vm with dummy provider [\#238](https://github.com/puppetlabs/vmpooler/issues/238)
- Any interest in VRA7 support? [\#235](https://github.com/puppetlabs/vmpooler/issues/235)
- Do not have a hardcoded list of VM providers [\#230](https://github.com/puppetlabs/vmpooler/issues/230)
- Use a dynamic check\_pool period [\#226](https://github.com/puppetlabs/vmpooler/issues/226)
- vmpooler doesn't seem to recognize ready VMs [\#218](https://github.com/puppetlabs/vmpooler/issues/218)
- `find_vmdks` in `vsphere_helper` should not use `vmdk_datastore._connection` [\#213](https://github.com/puppetlabs/vmpooler/issues/213)
- `get_base_vm_container_from` in `vsphere_helper` ensures the wrong connection [\#212](https://github.com/puppetlabs/vmpooler/issues/212)
- `close` in vsphere\_helper throws an error if a connection was never made [\#211](https://github.com/puppetlabs/vmpooler/issues/211)
- `find_pool` in vsphere\_helper.rb has subtle errors [\#210](https://github.com/puppetlabs/vmpooler/issues/210)
- `find_pool` in vsphere\_helper tends to throw instead of returning nil for missing pools [\#209](https://github.com/puppetlabs/vmpooler/issues/209)
- Vsphere connections are always insecure \(Ignore cert errors\) [\#207](https://github.com/puppetlabs/vmpooler/issues/207)
- `find_folder` in vsphere\_helper.rb has subtle errors [\#204](https://github.com/puppetlabs/vmpooler/issues/204)
- Should not use `abort` in vsphere\_helper [\#203](https://github.com/puppetlabs/vmpooler/issues/203)
- No reason why get\_snapshot\_list is defined in vsphere\_helper [\#202](https://github.com/puppetlabs/vmpooler/issues/202)
- Setting max\_tries in configuration results in vSphereHelper going into infinite loop [\#199](https://github.com/puppetlabs/vmpooler/issues/199)
- "connect.open" metric is doubled up if a connection is broken [\#195](https://github.com/puppetlabs/vmpooler/issues/195)
- Remove the use of global variables in the vSphere helper [\#194](https://github.com/puppetlabs/vmpooler/issues/194)
- Should exit Threads cleanly [\#193](https://github.com/puppetlabs/vmpooler/issues/193)
- check\_ready\_vm unnecessarily calls open\_socket [\#185](https://github.com/puppetlabs/vmpooler/issues/185)
- Feature Request: Add provider support [\#181](https://github.com/puppetlabs/vmpooler/issues/181)
- Document all possible HTTP response codes for endpoints [\#166](https://github.com/puppetlabs/vmpooler/issues/166)
- Add API to clone new VM from existing VM snapshot [\#165](https://github.com/puppetlabs/vmpooler/issues/165)
- vsphere\_helper.rb: find\_least\_used\_host should warn if no suitable hosts are found [\#164](https://github.com/puppetlabs/vmpooler/issues/164)
- find\_vm uses just hostname delta, vSphere searchIndex matches on FQDN [\#141](https://github.com/puppetlabs/vmpooler/issues/141)
- Tagging does not support boolean values [\#135](https://github.com/puppetlabs/vmpooler/issues/135)
- POST to /api/v1/token returns WEBrick::HTTPStatus::LengthRequired error [\#132](https://github.com/puppetlabs/vmpooler/issues/132)
- vmpooler throwing exceptions [\#129](https://github.com/puppetlabs/vmpooler/issues/129)
- NilClass error when running API without Graphite configured [\#81](https://github.com/puppetlabs/vmpooler/issues/81)
- Manually removing VM's result in state mis-match [\#80](https://github.com/puppetlabs/vmpooler/issues/80)
- Add support for customization specs [\#79](https://github.com/puppetlabs/vmpooler/issues/79)

**Merged pull requests:**

- \(maint\) Fix vmpooler require in bin/vmpooler [\#287](https://github.com/puppetlabs/vmpooler/pull/287) ([mattkirby](https://github.com/mattkirby))
- \(maint\) Remove ruby 2.2.10 from travis config [\#286](https://github.com/puppetlabs/vmpooler/pull/286) ([mattkirby](https://github.com/mattkirby))
- \(doc\) Add changelog and contributing guidlines [\#285](https://github.com/puppetlabs/vmpooler/pull/285) ([mattkirby](https://github.com/mattkirby))
- \(MAINT\) Remove find\_pool and update pending tests [\#283](https://github.com/puppetlabs/vmpooler/pull/283) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-109\) Allow API to run independently [\#281](https://github.com/puppetlabs/vmpooler/pull/281) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-81\) Add time remaining information [\#280](https://github.com/puppetlabs/vmpooler/pull/280) ([smcelmurry](https://github.com/smcelmurry))
- Revert "\(POOLER-81\) Add time\_remaining information" [\#279](https://github.com/puppetlabs/vmpooler/pull/279) ([smcelmurry](https://github.com/smcelmurry))
- \(MAINT\) Fix test reference to find\_vm [\#278](https://github.com/puppetlabs/vmpooler/pull/278) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-34\) Ship clone request to ready time to metrics [\#277](https://github.com/puppetlabs/vmpooler/pull/277) ([smcelmurry](https://github.com/smcelmurry))
- \(POOLER-81\) Add time\_remaining information [\#276](https://github.com/puppetlabs/vmpooler/pull/276) ([smcelmurry](https://github.com/smcelmurry))
- Add jruby 9.2 to travis testing [\#275](https://github.com/puppetlabs/vmpooler/pull/275) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-124\) Fix evaluation of max\_tries [\#273](https://github.com/puppetlabs/vmpooler/pull/273) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-40\) Do not return folders with get\_pool\_vms [\#272](https://github.com/puppetlabs/vmpooler/pull/272) ([mattkirby](https://github.com/mattkirby))
- Ensure template deltas are created once [\#271](https://github.com/puppetlabs/vmpooler/pull/271) ([mattkirby](https://github.com/mattkirby))
- Do not run duplicate instances of inventory check for a pool [\#270](https://github.com/puppetlabs/vmpooler/pull/270) ([mattkirby](https://github.com/mattkirby))
- Eliminate duplicate VM object lookups where possible [\#269](https://github.com/puppetlabs/vmpooler/pull/269) ([mattkirby](https://github.com/mattkirby))
- Reduce object lookups for finding folders [\#268](https://github.com/puppetlabs/vmpooler/pull/268) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-113\) Add support for multiple LDAP search bases [\#267](https://github.com/puppetlabs/vmpooler/pull/267) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-31\) Expire redis vm key when clone fails [\#266](https://github.com/puppetlabs/vmpooler/pull/266) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-112\) Ensure a VM is only destroyed once [\#265](https://github.com/puppetlabs/vmpooler/pull/265) ([mattkirby](https://github.com/mattkirby))
- Adds a gemspec file [\#264](https://github.com/puppetlabs/vmpooler/pull/264) ([logicminds](https://github.com/logicminds))
- Change default vsphere connection behavior [\#261](https://github.com/puppetlabs/vmpooler/pull/261) ([mattkirby](https://github.com/mattkirby))
- Remove propertyCollector from add\_disk [\#260](https://github.com/puppetlabs/vmpooler/pull/260) ([mattkirby](https://github.com/mattkirby))
- Update ruby versions for travis [\#259](https://github.com/puppetlabs/vmpooler/pull/259) ([mattkirby](https://github.com/mattkirby))
- Update to generic launcher [\#258](https://github.com/puppetlabs/vmpooler/pull/258) ([frozenfoxx](https://github.com/frozenfoxx))
- Add support for setting redis port and password [\#257](https://github.com/puppetlabs/vmpooler/pull/257) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-107\) Add configuration API endpoint [\#256](https://github.com/puppetlabs/vmpooler/pull/256) ([mattkirby](https://github.com/mattkirby))
- Create vmpooler.service [\#255](https://github.com/puppetlabs/vmpooler/pull/255) ([frozenfoxx](https://github.com/frozenfoxx))
- \(POOLER-101\) Update nokogiri and net-ldap [\#254](https://github.com/puppetlabs/vmpooler/pull/254) ([mattkirby](https://github.com/mattkirby))
- Add dockerfile without redis [\#253](https://github.com/puppetlabs/vmpooler/pull/253) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-103\) Fix configuration file loading [\#252](https://github.com/puppetlabs/vmpooler/pull/252) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-68\) Replace find\_vm search mechanism [\#251](https://github.com/puppetlabs/vmpooler/pull/251) ([mattkirby](https://github.com/mattkirby))
- \(maint\) Add the last boot time for each pool [\#250](https://github.com/puppetlabs/vmpooler/pull/250) ([sbeaulie](https://github.com/sbeaulie))
- Fix typo in error message [\#249](https://github.com/puppetlabs/vmpooler/pull/249) ([teancom](https://github.com/teancom))
- Identify when ESXi host quickstats do not return [\#248](https://github.com/puppetlabs/vmpooler/pull/248) ([mattkirby](https://github.com/mattkirby))
- Update jruby version for travis to 9.1.13.0 [\#247](https://github.com/puppetlabs/vmpooler/pull/247) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-96\) Setting the Rubygems version [\#246](https://github.com/puppetlabs/vmpooler/pull/246) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-93\) Extend API endpoint to provide just what is needed [\#245](https://github.com/puppetlabs/vmpooler/pull/245) ([sbeaulie](https://github.com/sbeaulie))
- \(POOLER-92\) Add the alias information in the API status page for each… [\#244](https://github.com/puppetlabs/vmpooler/pull/244) ([sbeaulie](https://github.com/sbeaulie))
- \(QENG-5305\) Improve vmpooler host selection [\#242](https://github.com/puppetlabs/vmpooler/pull/242) ([mattkirby](https://github.com/mattkirby))
- Allow user to specify a configuration file in VMPOOLER\_CONFIG\_FILE variable [\#241](https://github.com/puppetlabs/vmpooler/pull/241) ([adamdav](https://github.com/adamdav))
- Fix no implicit conversion to rational from nil [\#239](https://github.com/puppetlabs/vmpooler/pull/239) ([sbeaulie](https://github.com/sbeaulie))
- Updated Vagrant box and associated docs [\#237](https://github.com/puppetlabs/vmpooler/pull/237) ([genebean](https://github.com/genebean))
- \(GH-226\) Respond quickly to VMs being consumed [\#236](https://github.com/puppetlabs/vmpooler/pull/236) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-89\) Identify when config issue is present [\#234](https://github.com/puppetlabs/vmpooler/pull/234) ([mattkirby](https://github.com/mattkirby))
- \(maint\) Update template delta script for moved vsphere credentials [\#233](https://github.com/puppetlabs/vmpooler/pull/233) ([ScottGarman](https://github.com/ScottGarman))
- Fix rubocop [\#232](https://github.com/puppetlabs/vmpooler/pull/232) ([glennsarti](https://github.com/glennsarti))
- \(GH-230\) Dynamically load VM Providers [\#231](https://github.com/puppetlabs/vmpooler/pull/231) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Remove phantom VMs that are in Redis but don't exist in provider [\#229](https://github.com/puppetlabs/vmpooler/pull/229) ([glennsarti](https://github.com/glennsarti))
- Update find\_least\_used\_compatible\_host to specify pool [\#228](https://github.com/puppetlabs/vmpooler/pull/228) ([mattkirby](https://github.com/mattkirby))
- \(GH-226\) Use a dynamic pool\_check loop period [\#227](https://github.com/puppetlabs/vmpooler/pull/227) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Update development documentation [\#225](https://github.com/puppetlabs/vmpooler/pull/225) ([glennsarti](https://github.com/glennsarti))
- \(GH-213\) Remove use of private \_connection method [\#224](https://github.com/puppetlabs/vmpooler/pull/224) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-83\) Add ability to specify a datacenter for vsphere [\#223](https://github.com/puppetlabs/vmpooler/pull/223) ([glennsarti](https://github.com/glennsarti))
- Added Vagrant setup and fixed the Dockerfile so it actually works [\#222](https://github.com/puppetlabs/vmpooler/pull/222) ([genebean](https://github.com/genebean))
- Adding support for multiple vsphere providers [\#221](https://github.com/puppetlabs/vmpooler/pull/221) ([sbeaulie](https://github.com/sbeaulie))
- Refactor get\_cluster\_host\_utilization method [\#220](https://github.com/puppetlabs/vmpooler/pull/220) ([sbeaulie](https://github.com/sbeaulie))
- \(maint\) Pin rack to 1.x [\#219](https://github.com/puppetlabs/vmpooler/pull/219) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-72\)\(POOLER-70\)\(POOLER-52\) Move Pool Manager to use the VM Provider [\#216](https://github.com/puppetlabs/vmpooler/pull/216) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Emit console messages when debugging is enabled [\#215](https://github.com/puppetlabs/vmpooler/pull/215) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-70\)\(POOLER-52\) Create a functional vSphere Provider  [\#214](https://github.com/puppetlabs/vmpooler/pull/214) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Fix rubocop violations  [\#208](https://github.com/puppetlabs/vmpooler/pull/208) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Fix credentials in vsphere\_helper [\#200](https://github.com/puppetlabs/vmpooler/pull/200) ([glennsarti](https://github.com/glennsarti))
- Update usage of global variablesin vsphere\_helper [\#198](https://github.com/puppetlabs/vmpooler/pull/198) ([mattkirby](https://github.com/mattkirby))
- Remove duplicate of metrics.connect.open [\#197](https://github.com/puppetlabs/vmpooler/pull/197) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-73\) Add spec tests for vsphere\_helper [\#196](https://github.com/puppetlabs/vmpooler/pull/196) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Fix rubocop offenses [\#191](https://github.com/puppetlabs/vmpooler/pull/191) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-70\) Prepare to refactor VSphere code into a VM Provider [\#190](https://github.com/puppetlabs/vmpooler/pull/190) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-70\) Refactor clone\_vm to take pool configuration object [\#189](https://github.com/puppetlabs/vmpooler/pull/189) ([glennsarti](https://github.com/glennsarti))
- \(GH-185\) Remove unnecessary checks in check\_ready\_vm  [\#188](https://github.com/puppetlabs/vmpooler/pull/188) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Only load rubocop rake tasks if gem is available [\#187](https://github.com/puppetlabs/vmpooler/pull/187) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Add rubocop and allow failures in Travis CI [\#183](https://github.com/puppetlabs/vmpooler/pull/183) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-73\) Update unit tests prior to refactoring [\#182](https://github.com/puppetlabs/vmpooler/pull/182) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-71\) Add dummy authentication provider [\#180](https://github.com/puppetlabs/vmpooler/pull/180) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Remove Ruby 1.9.3 testing from Travis [\#178](https://github.com/puppetlabs/vmpooler/pull/178) ([glennsarti](https://github.com/glennsarti))
- \(maint\) Enhance VM Pooler developer experience [\#177](https://github.com/puppetlabs/vmpooler/pull/177) ([glennsarti](https://github.com/glennsarti))
- \(POOLER-47\) Send clone errors up [\#175](https://github.com/puppetlabs/vmpooler/pull/175) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-48\) Clear migrations at application start time [\#174](https://github.com/puppetlabs/vmpooler/pull/174) ([mattkirby](https://github.com/mattkirby))
- Add retry logic with a delay for vsphere connections [\#173](https://github.com/puppetlabs/vmpooler/pull/173) ([mattkirby](https://github.com/mattkirby))
- \(POOLER-44\) Fix vmpooler.migrate reference [\#172](https://github.com/puppetlabs/vmpooler/pull/172) ([mattkirby](https://github.com/mattkirby))
- Add `puma` as required gem [\#171](https://github.com/puppetlabs/vmpooler/pull/171) ([sschneid](https://github.com/sschneid))
- Fix JavaScript error on nil `weekly_data` [\#170](https://github.com/puppetlabs/vmpooler/pull/170) ([sschneid](https://github.com/sschneid))
- Containerize vmpooler [\#169](https://github.com/puppetlabs/vmpooler/pull/169) ([sschneid](https://github.com/sschneid))
- Add vagrant-vmpooler plugin to readme [\#168](https://github.com/puppetlabs/vmpooler/pull/168) ([briancain](https://github.com/briancain))
- Improve vmpooler scheduling logic [\#167](https://github.com/puppetlabs/vmpooler/pull/167) ([mattkirby](https://github.com/mattkirby))
- \[QENG-4181\] Add per-pool stats to `/status` API [\#162](https://github.com/puppetlabs/vmpooler/pull/162) ([rick](https://github.com/rick))
- Merge CI.next into Master [\#161](https://github.com/puppetlabs/vmpooler/pull/161) ([shermdog](https://github.com/shermdog))
- \(maint\) update README.md and LICENSE to reflect rebranding [\#157](https://github.com/puppetlabs/vmpooler/pull/157) ([erosa](https://github.com/erosa))
- Add info about vmfloaty [\#156](https://github.com/puppetlabs/vmpooler/pull/156) ([briancain](https://github.com/briancain))
- Added IP lookup functionality for /vm/hostname [\#154](https://github.com/puppetlabs/vmpooler/pull/154) ([frozenfoxx](https://github.com/frozenfoxx))
- Improved tests for vmpooler [\#152](https://github.com/puppetlabs/vmpooler/pull/152) ([rick](https://github.com/rick))
- Added prefix parameter to the vmpooler configuration [\#149](https://github.com/puppetlabs/vmpooler/pull/149) ([frozenfoxx](https://github.com/frozenfoxx))
- Update license copyright [\#148](https://github.com/puppetlabs/vmpooler/pull/148) ([sschneid](https://github.com/sschneid))
- Allow new disks to be added to running VMs via vmpooler API [\#147](https://github.com/puppetlabs/vmpooler/pull/147) ([sschneid](https://github.com/sschneid))
- Updated YAML config variables in create\_template\_deltas.rb [\#145](https://github.com/puppetlabs/vmpooler/pull/145) ([frozenfoxx](https://github.com/frozenfoxx))
- \(QA-2036\) Update README for Client Utility [\#143](https://github.com/puppetlabs/vmpooler/pull/143) ([cowofevil](https://github.com/cowofevil))
- add guestinfo.hostname to VirtualMachineConfigSpecs [\#139](https://github.com/puppetlabs/vmpooler/pull/139) ([heathseals](https://github.com/heathseals))
- \(QENG-2807\) Allow pool 'alias' names [\#138](https://github.com/puppetlabs/vmpooler/pull/138) ([sschneid](https://github.com/sschneid))
- \(QENG-2995\) Display associated VMs in GET /token/:token endpoint [\#137](https://github.com/puppetlabs/vmpooler/pull/137) ([sschneid](https://github.com/sschneid))
- Update API docs to include "domain" key for get vm requests [\#136](https://github.com/puppetlabs/vmpooler/pull/136) ([briancain](https://github.com/briancain))
- \(MAINT\) Remove Ping Check on Running VMs [\#133](https://github.com/puppetlabs/vmpooler/pull/133) ([colinPL](https://github.com/colinPL))
- \(maint\) Move VM Only When SSH Check Succeeds [\#131](https://github.com/puppetlabs/vmpooler/pull/131) ([colinPL](https://github.com/colinPL))
- \(QENG-2952\) Check that SSH is available [\#130](https://github.com/puppetlabs/vmpooler/pull/130) ([sschneid](https://github.com/sschneid))
- \(maint\) Update license copyright [\#128](https://github.com/puppetlabs/vmpooler/pull/128) ([sschneid](https://github.com/sschneid))
- \(maint\) Remove duplicate \(nested\) "ok" responses [\#127](https://github.com/puppetlabs/vmpooler/pull/127) ([sschneid](https://github.com/sschneid))
- \(maint\) Documentation updates [\#126](https://github.com/puppetlabs/vmpooler/pull/126) ([sschneid](https://github.com/sschneid))
- Track token use times [\#125](https://github.com/puppetlabs/vmpooler/pull/125) ([sschneid](https://github.com/sschneid))
- Docs update [\#124](https://github.com/puppetlabs/vmpooler/pull/124) ([sschneid](https://github.com/sschneid))
- User token list [\#123](https://github.com/puppetlabs/vmpooler/pull/123) ([sschneid](https://github.com/sschneid))
- \(maint\) Additional utility and reporting scripts [\#122](https://github.com/puppetlabs/vmpooler/pull/122) ([sschneid](https://github.com/sschneid))
- \(maint\) Syntax fixup [\#121](https://github.com/puppetlabs/vmpooler/pull/121) ([sschneid](https://github.com/sschneid))
- \(MAINT\) Reduce redis Calls in API [\#120](https://github.com/puppetlabs/vmpooler/pull/120) ([colinPL](https://github.com/colinPL))
- \(maint\) Use expect\_json helper method for determining JSON response status [\#119](https://github.com/puppetlabs/vmpooler/pull/119) ([sschneid](https://github.com/sschneid))
- \(QENG-1304\) vmpooler should require an auth key for VM destruction [\#118](https://github.com/puppetlabs/vmpooler/pull/118) ([sschneid](https://github.com/sschneid))
- \(QENG-2636\) Host snapshots [\#117](https://github.com/puppetlabs/vmpooler/pull/117) ([sschneid](https://github.com/sschneid))
- \(maint\) Use dep caching and containers [\#116](https://github.com/puppetlabs/vmpooler/pull/116) ([sschneid](https://github.com/sschneid))
- \(maint\) Include travis-ci build status in README [\#115](https://github.com/puppetlabs/vmpooler/pull/115) ([sschneid](https://github.com/sschneid))
- Show test contexts and names [\#114](https://github.com/puppetlabs/vmpooler/pull/114) ([sschneid](https://github.com/sschneid))
- \(QENG-2246\) Add Default Rake Task [\#113](https://github.com/puppetlabs/vmpooler/pull/113) ([colinPL](https://github.com/colinPL))
- Log empty pools [\#112](https://github.com/puppetlabs/vmpooler/pull/112) ([sschneid](https://github.com/sschneid))
- \(QENG-2246\) Add Travis CI [\#111](https://github.com/puppetlabs/vmpooler/pull/111) ([colinPL](https://github.com/colinPL))
- \(QENG-2388\) Tagging restrictions [\#110](https://github.com/puppetlabs/vmpooler/pull/110) ([sschneid](https://github.com/sschneid))
- An updated dashboard [\#109](https://github.com/puppetlabs/vmpooler/pull/109) ([sschneid](https://github.com/sschneid))
- API summary rework [\#108](https://github.com/puppetlabs/vmpooler/pull/108) ([sschneid](https://github.com/sschneid))
- Only filter regex matches [\#106](https://github.com/puppetlabs/vmpooler/pull/106) ([sschneid](https://github.com/sschneid))
- \(QENG-2518\) Tag-filtering [\#105](https://github.com/puppetlabs/vmpooler/pull/105) ([sschneid](https://github.com/sschneid))
- \(QENG-2360\) check\_running\_vm Spec Tests [\#104](https://github.com/puppetlabs/vmpooler/pull/104) ([colinPL](https://github.com/colinPL))
- \(QENG-2056\) Create daily tag indexes, report in /summary [\#102](https://github.com/puppetlabs/vmpooler/pull/102) ([sschneid](https://github.com/sschneid))
- Store token metadata in vmpooler\_\_vm\_\_ Redis hash [\#101](https://github.com/puppetlabs/vmpooler/pull/101) ([sschneid](https://github.com/sschneid))
- Display VM state in GET /vm/:hostname route [\#100](https://github.com/puppetlabs/vmpooler/pull/100) ([sschneid](https://github.com/sschneid))
- Add basic auth token functionality [\#98](https://github.com/puppetlabs/vmpooler/pull/98) ([sschneid](https://github.com/sschneid))
- Add basic HTTP authentication and /token routes [\#97](https://github.com/puppetlabs/vmpooler/pull/97) ([sschneid](https://github.com/sschneid))
- \(QENG-2208\) Add more helper tests [\#95](https://github.com/puppetlabs/vmpooler/pull/95) ([colinPL](https://github.com/colinPL))
- \(QENG-2208\) Move Sinatra Helpers to own file [\#94](https://github.com/puppetlabs/vmpooler/pull/94) ([colinPL](https://github.com/colinPL))
- Fix rspec tests broken in f9de28236b726e37977123cea9b4f3a562bfdcdb [\#93](https://github.com/puppetlabs/vmpooler/pull/93) ([sschneid](https://github.com/sschneid))
- Redirect / to /dashboard [\#92](https://github.com/puppetlabs/vmpooler/pull/92) ([sschneid](https://github.com/sschneid))
- Ensure 'lifetime' val returned by GET /vm/:hostname is an int [\#91](https://github.com/puppetlabs/vmpooler/pull/91) ([sschneid](https://github.com/sschneid))
- running-to-lifetime comparison should be 'greater than or equal to' [\#90](https://github.com/puppetlabs/vmpooler/pull/90) ([sschneid](https://github.com/sschneid))
- Auto-expire Redis metadata key via Redis EXPIRE [\#89](https://github.com/puppetlabs/vmpooler/pull/89) ([sschneid](https://github.com/sschneid))
- \(QENG-1906\) Add specs for Dashboard and root API class [\#88](https://github.com/puppetlabs/vmpooler/pull/88) ([colinPL](https://github.com/colinPL))
- \(maint\) Fix bad redis reference [\#87](https://github.com/puppetlabs/vmpooler/pull/87) ([colinPL](https://github.com/colinPL))
- \(QENG-1906\) Break apart check\_pending\_vm and add spec tests [\#86](https://github.com/puppetlabs/vmpooler/pull/86) ([colinPL](https://github.com/colinPL))
- Remove defined? when checking configuration for graphite server. [\#85](https://github.com/puppetlabs/vmpooler/pull/85) ([colinPL](https://github.com/colinPL))
- \(QENG-1906\) Add spec tests for Janitor [\#78](https://github.com/puppetlabs/vmpooler/pull/78) ([colinPL](https://github.com/colinPL))
- \(QENG-1906\) Refactor initialize to allow config passing [\#77](https://github.com/puppetlabs/vmpooler/pull/77) ([colinPL](https://github.com/colinPL))
- Use 'checkout' time to calculate 'running' time [\#75](https://github.com/puppetlabs/vmpooler/pull/75) ([sschneid](https://github.com/sschneid))
- Catch improperly-formatted data payloads [\#73](https://github.com/puppetlabs/vmpooler/pull/73) ([sschneid](https://github.com/sschneid))
- \(QENG-1905\) Adding VM-tagging support via PUT /vm/:hostname endpoint [\#72](https://github.com/puppetlabs/vmpooler/pull/72) ([sschneid](https://github.com/sschneid))
- \(QENG-2057\) Historic Redis VM metadata [\#71](https://github.com/puppetlabs/vmpooler/pull/71) ([sschneid](https://github.com/sschneid))
- \(QENG-1899\) Add documentation for /summary [\#67](https://github.com/puppetlabs/vmpooler/pull/67) ([colinPL](https://github.com/colinPL))
- Use $redis.hgetall rather than hget in a loop [\#66](https://github.com/puppetlabs/vmpooler/pull/66) ([sschneid](https://github.com/sschneid))
- /summary per-pool metrics [\#65](https://github.com/puppetlabs/vmpooler/pull/65) ([sschneid](https://github.com/sschneid))
- Show boot metrics in /status and /summary endpoints [\#64](https://github.com/puppetlabs/vmpooler/pull/64) ([sschneid](https://github.com/sschneid))
- \(maint\) Fixing spacing [\#63](https://github.com/puppetlabs/vmpooler/pull/63) ([sschneid](https://github.com/sschneid))
- Metric calc via helpers [\#62](https://github.com/puppetlabs/vmpooler/pull/62) ([sschneid](https://github.com/sschneid))
- More granular metrics [\#61](https://github.com/puppetlabs/vmpooler/pull/61) ([sschneid](https://github.com/sschneid))



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
