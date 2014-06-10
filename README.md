![vmpooler](https://raw.github.com/sschneid/vmpooler/master/lib/vmpooler/public/img/logo.jpg)

# vmpooler

vmpooler provides configurable 'pools' of available (running) virtual machines.


## Usage

At [Puppet Labs](http://puppetlabs.com) we run acceptance tests on hundreds of disposable VMs every day.  Dynamic cloning of VM templates initially worked fine for this, but added several seconds to each test run and was unable to account for failed clone tasks.  By pushing these operations to a backend service, we were able to both speed up tests and eliminate test failures due to underlying infrastructure failures.


## Installation

### Prerequisites

vmpooler requires the following Ruby gems be installed:

- [json](http://rubygems.org/gems/json)
- [rbvmomi](http://rubygems.org/gems/rbvmomi)
- [redis](http://rubygems.org/gems/redis)
- [sinatra](http://rubygems.org/gems/sinatra)

It also requires that a [Redis](http://redis.io/) server exists somewhere, as this is the datastore used for vmpooler's inventory and queueing services.

### Configuration

The following YAML configuration sets up two pools, `debian-7-i386` and `debian-7-x86_64`, which contain 5 running VMs each:

```
---
:vsphere:
  server: 'vsphere.company.com'
  username: 'vmpooler'
  password: 'swimsw1msw!m'

:redis:
  server: 'redis.company.com'

:config:
  logfile: '/var/log/vmpooler.log'

:pools:
  - name: 'debian-7-i386'
    template: 'Templates/debian-7-i386'
    folder: 'Pooled VMs/debian-7-i386'
    pool: 'Pooled VMs/debian-7-i386'
    datastore: 'vmstorage'
    size: 5
  - name: 'debian-7-x86_64'
    template: 'Templates/debian-7-x86_64'
    folder: 'Pooled VMs/debian-7-x86_64'
    pool: 'Pooled VMs/debian-7-x86_64'
    datastore: 'vmstorage'
    size: 5
```

See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for additional configuration options and parameters.

### Template set-up

Template set-up is left as an exercise to the reader.  Somehow, either via PXE, embedded bootstrap scripts, or some other method -- clones of VM templates need to be able to set their hostname, register themselves in your DNS, and be resolvable by the vmpooler application after completing the clone task and booting up.


## API and Dashboard

vmpooler provides an API and web front-end (dashboard) on port `:4567`.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), to specify an alternative port to listen on.

### API

vmpooler provides a REST API for VM management.  The following examples use `curl` for communication.

#### GET /vm

Retrieve a list of available VM pools.

```
$ curl --url vmpooler.company.com/vm
```
```json
[
  "debian-7-i386",
  "debian-7-x86_64"
]
```

#### POST /vm
Useful for batch operations; post JSON (see format below), get back VMs.

```
$ curl -d '{"debian-7-i386":"2","debian-7-x86_64":"1"}' --url vmpooler.company.com/vm
```
```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": [
      "o41xtodlvnvu5cw",
      "khirruvwfjlmx3y"
    ]
  },
  "debian-7-x86_64": {
    "hostname": "y91qbrpbfj6d13q"
  }
}
```

#### POST /vm/<pool>
Check-out a VM or VMs.

```
$ curl -d --url vmpooler.company.com/vm/debian-7-i386
```
```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": "fq6qlpjlsskycq6"
  }
}
```

Multiple VMs can be requested by using multiple query parameters in the URL:

```
$ curl -d --url vmpooler.company.com/vm/debian-7-i386+debian-7-i386+debian-7-x86_64
```

```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": [
      "sc0o4xqtodlul5w",
      "4m4dkhqiufnjmxy"
    ]
  },
  "debian-7-x86_64": {
    "hostname": "zb91y9qbrbf6d3q"
  }
}
```

#### DELETE /vm/<hostnamename>

Schedule a checked-out VM for deletion.

```
$ curl -X DELETE --url vmpooler.company.com/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

### Dashboard

A dashboard is provided to offer real-time statistics and historical graphs.  It looks like this in a large installation on a fairly busy day:

![dashboard](https://raw.github.com/sschneid/vmpooler/gh-pages/img/screenshots/dashboard.png)

[Graphite](http://graphite.wikidot.com/) is required for historical data retrieval.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for details.


## Authors and Contributors

- Scott Schneider (sschneid@gmail.com)


## License

vmpooler is distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).  See the [LICENSE](LICENSE) file for more details.

