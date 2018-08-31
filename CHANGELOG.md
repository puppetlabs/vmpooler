# Change Log

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](http://keepachangelog.com)
& makes a strong effort to adhere to
[Semantic Versioning](http://semver.org).

Tracking in this Changelog began for this project with the tagging of version 0.1.0.
If you're looking for changes from before this, refer to the project's
git logs & PR history.

# [Unreleased](https://github.com/puppetlabs/vmpooler/compare/0.2.0...master)
- Better handle delta disk creation errors (POOLER-130)

### Added
- Re-write check\_pool in pool\_manager to improve readability
- Add a docker-compose file for testing vmpooler

# [0.2.0](https://github.com/puppetlabs/vmpooler/compare/0.1.0...0.2.0)

### Fixed
- (POOLER-128) VM specific mutex objects are not dereferenced when a VM is destroyed
- A VM that is being destroyed is reported as discovered

### Added
- Adds a new mechanism to load providers from any gem or file path

# [0.1.0](https://github.com/puppetlabs/vmpooler/compare/4c858d012a262093383e57ea6db790521886d8d4...master)

### Fixed
- Remove unused method `find_pool` and related pending tests
- Setting `max_tries` results in an infinite loop (POOLER-124)
- Do not evaluate folders as VMs in `get_pool_vms` (POOLER-40)
- Expire redis VM key when clone fails (POOLER-31)
- Remove all usage of propertyCollector
- Replace `find_vm` search mechanism (POOLER-68)
- Fix configuration file loading (POOLER-103)
- Update vulnerable dependencies (POOLER-101)

### Added

- Allow API and manager to run separately (POOLER-109)
- Add configuration API endpoint (POOLER-107)
- Add option to disable VM hostname mismatch checks
- Add a gemspec file
- Add time remaining information (POOLER-81)
- Ship metrics for clone to ready time (POOLER-34)
- Reduce duplicate checking of VMs
- Reduce object lookups when retrieving VMs and folders
- Optionally create delta disks for pool templates
- Drop support for any ruby before 2.3
- Add support for multiple LDAP search base DNs (POOLER-113)
- Ensure a VM is only destroyed once (POOLER-112)
- Add support for setting redis server port and password
- Greatly reduce time it takes to add disks
- Add Dockerfile that does not bundle redis
- Add vmpooler.service to support systemd managing the service
