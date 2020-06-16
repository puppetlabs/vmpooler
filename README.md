![vmpooler](https://raw.github.com/sschneid/vmpooler/master/lib/vmpooler/public/img/logo.gif)

# vmpooler

vmpooler provides configurable 'pools' of instantly-available (running) virtual machines.


## Usage

At [Puppet, Inc.](http://puppet.com) we run acceptance tests on thousands of disposable VMs every day. Vmpooler manages the lifecycle of these VMs from request through deletion, with options available to pool ready instances, and provision on demand.

## Installation

### Prerequisites

vmpooler is available as a gem

To use the gem `gem install vmpooler`

### Dependencies

Vmpooler requires a [Redis](http://redis.io/) server. This is the datastore used for vmpooler's inventory and queueing services.

### Configuration

Configuration for vmpooler may be provided via environment variables, or a configuration file.

Note on jruby 9.2.11.x: We have found when running vmpooler on jruby 9.2.11.x we occasionally encounter a stack overflow error that causes the pool\_manager application component to fail and stop doing work. To address this issue on jruby 9.2.11.x we recommend setting the jruby option 'invokedynamic.yield=false'. To set this with jruby 9.2.11.1 you can specify the environment variable 'JRUBY\_OPTS' with the value '-Xinvokedynamic.yield=false'.

The provided configuration defaults are reasonable for  small vmpooler instances with a few pools. If you plan to run a large vmpooler instance it is important to consider configuration values appropriate for the instance of your size in order to avoid starving the provider, or redis, of connections.

As of vmpooler 0.13.x redis uses a connection pool to improve efficiency and ensure thread safe usage. At Puppet, we run an instance with about 100 pools at any given time. We have to provide it with 200 redis connections to the redis connection pool, and a timeout for connections of 40 seconds, to avoid timeouts. Because metrics are generated for connection available and waited your metrics provider will need to be able to cope with this volume. Statsd is recommended to ensure metrics get delivered reliably.

Please see this [configuration](docs/configuration.md) document for more details about configuring vmpooler via environment variables.

The following YAML configuration sets up two pools, `debian-7-i386` and `debian-7-x86_64`, which contain 5 running VMs each:

```
---
:providers:
  :vsphere:
    server: 'vsphere.example.com'
    username: 'vmpooler'
    password: 'swimsw1msw!m'

:redis:
  server: 'redis.example.com'

:config:
  logfile: '/var/log/vmpooler.log'

:pools:
  - name: 'debian-7-i386'
    template: 'Templates/debian-7-i386'
    folder: 'Pooled VMs/debian-7-i386'
    pool: 'Pooled VMs/debian-7-i386'
    datastore: 'vmstorage'
    size: 5
    provider: vsphere
  - name: 'debian-7-x86_64'
    template: 'Templates/debian-7-x86_64'
    folder: 'Pooled VMs/debian-7-x86_64'
    pool: 'Pooled VMs/debian-7-x86_64'
    datastore: 'vmstorage'
    size: 5
    provider: vsphere
```

See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for additional configuration options and parameters or for supporting multiple providers.

### Running via Docker

A [Dockerfile](/docker/Dockerfile) is included in this repository to allow running vmpooler inside a Docker container. A configuration file can be used via volume mapping, and specifying the destination as the configuration file via environment variables, or the application can be configured with environment variables alone. The Dockerfile provides an entrypoint so you may choose whether to run API, or manager services. The default behavior will run both. To build and run:

```
docker build -t vmpooler . && docker run -e VMPOOLER_CONFIG -p 80:4567 -it vmpooler
```

To run only the API and dashboard

```
docker run -p 80:4567 -it vmpooler api
```

To run only the manager component

```
docker run -it vmpooler manager
```

### docker-compose

A docker-compose file is provided to support running vmpooler easily via docker-compose. This is useful for development because your local code is used to build the gem used in the docker-compose environment.

```
docker-compose -f docker/docker-compose.yml up
```

### Running Docker inside Vagrant

A vagrantfile is included in this repository. Please see [vagrant instructions](docs/vagrant.md) for details.

## API and Dashboard

vmpooler provides an API and web front-end (dashboard) on port `:4567`.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), to specify an alternative port to listen on.

### API

vmpooler provides a REST API for VM management.  See the [API documentation](docs/API.md) for more information.

### Dashboard

A dashboard is provided to offer real-time statistics and historical graphs.  It looks like this:

![dashboard](https://raw.github.com/sschneid/vmpooler/gh-pages/img/screenshots/dashboard.png)

[Graphite](http://graphite.wikidot.com/) is required for historical data retrieval.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for details.

## Command-line Utility

- [vmfloaty](https://github.com/briancain/vmfloaty) is a ruby based CLI tool and scripting library written in ruby.

## Vagrant plugin

- [vagrant-vmpooler](https://github.com/briancain/vagrant-vmpooler) Use Vagrant to create and manage your vmpooler instances.

## Development and further documentation

For more information about setting up a development instance of vmpooler or other subjects, see the [docs/](docs) directory.

## Build status

[![Build Status](https://travis-ci.org/puppetlabs/vmpooler.png?branch=master)](https://travis-ci.org/puppetlabs/vmpooler)


## License

vmpooler is distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).  See the [LICENSE](LICENSE) file for more details.
