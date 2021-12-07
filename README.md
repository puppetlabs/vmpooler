![VMPooler](lib/vmpooler/public/img/logo.png)

# VMPooler

VMPooler provides configurable 'pools' of instantly-available (pre-provisioned) and/or on-demand (provisioned on request) virtual machines.

## Usage

At [Puppet, Inc.](http://puppet.com) we run acceptance tests on thousands of disposable VMs every day. VMPooler manages the life cycle of these VMs from request through deletion, with options available to pool ready instances, and provision on demand.

### v2.0.0 note

As of version 2.0.0, all providers other than the dummy one are now separate gems. Historically the vSphere provider was included within VMPooler itself. That code has been moved to the [puppetlabs/vmpooler-provider-vsphere](https://github.com/puppetlabs/vmpooler-provider-vsphere) repository and the `vmpooler-provider-vsphere` gem. To migrate from VMPooler 1.x to 2.0 you will need to ensure that `vmpooler-provider-vsphere` is installed along side the `vmpooler` gem. See the  [Provider API](docs/PROVIDER_API.md) docs for more information.

## Installation

### Prerequisites

VMPooler is available as a gem. To use the gem run `gem install vmpooler` or add it to your Gemfile and install via bundler. You will also need to install any needed providers in the same manner.

### Dependencies

VMPooler requires a [Redis](http://redis.io/) server. This is the data store used for VMPooler's inventory and queuing services.

### Configuration

Configuration for VMPooler may be provided via environment variables, or a configuration file.

#### Note on JRuby 9.2.11.x

We have found when running VMPooler on JRuby 9.2.11.x we occasionally encounter a stack overflow error that causes the pool\_manager application component to fail and stop doing work. To address this issue on JRuby 9.2.11.x we recommend setting the JRuby option `invokedynamic.yield=false`. To set this with JRuby 9.2.11.1 you can specify the environment variable `JRUBY_OPTS` with the value `-Xinvokedynamic.yield=false`.

The provided configuration defaults are reasonable for  small VMPooler instances with a few pools. If you plan to run a large VMPooler instance it is important to consider configuration values appropriate for the instance of your size in order to avoid starving the provider, or Redis, of connections.

VMPooler uses a connection pool for Redis to improve efficiency and ensure thread safe usage. At Puppet, we run an instance with about 100 pools at any given time. We have to provide it with 200 Redis connections to the Redis connection pool, and a timeout for connections of 40 seconds, to avoid timeouts. Because metrics are generated for connection available and waited, your metrics provider will need to be able to cope with this volume. Prometheus or StatsD is recommended to ensure metrics get delivered reliably.

Please see this [configuration](docs/configuration.md) document for more details about configuring VMPooler via environment variables.

The following YAML configuration sets up two pools, `debian-7-i386` and `debian-7-x86_64`, which contain 5 running VMs each:

```yaml
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

A [Dockerfile](/docker/Dockerfile) is included in this repository to allow running VMPooler inside a Docker container. A configuration file can be used via volume mapping, and specifying the destination as the configuration file via environment variables, or the application can be configured with environment variables alone. The Dockerfile provides an entrypoint so you may choose whether to run API, or manager services. The default behavior will run both. To build and run:

```bash
docker build -t vmpooler . && docker run -e VMPOOLER_CONFIG -p 80:4567 -it vmpooler
```

To run only the API and dashboard:

```bash
docker run -p 80:4567 -it vmpooler api
```

To run only the manager component:

```bash
docker run -it vmpooler manager
```

### docker-compose

A docker-compose file is provided to support running VMPooler easily via docker-compose. This is useful for development because your local code is used to build the gem used in the docker-compose environment.

```bash
docker-compose -f docker/docker-compose.yml up
```

### Running Docker inside Vagrant

A Vagrantfile is included in this repository. Please see [vagrant instructions](docs/vagrant.md) for details.

## API and Dashboard

VMPooler provides an API and web front-end (dashboard) on port `:4567`.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), to specify an alternative port to listen on.

### API

VMPooler provides a REST API for VM management.  See the [API documentation](docs/API.md) for more information.

### Dashboard

A dashboard is provided to offer real-time statistics and historical graphs.  It looks like this:

![dashboard](https://raw.github.com/sschneid/vmpooler/gh-pages/img/screenshots/dashboard.png)

[Graphite](http://graphite.wikidot.com/) is required for historical data retrieval.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for details.

## Related tools and resources

### Command-line Utility

- [vmfloaty](https://github.com/puppetlabs/vmfloaty) is a ruby based CLI tool and scripting library. We consider it the primary way for users to interact with VMPooler.

### Vagrant plugin

- [vagrant-vmpooler](https://github.com/briancain/vagrant-vmpooler): Use Vagrant to create and manage your VMPooler instances.

## Development and further documentation

For more information about setting up a development instance of VMPooler or other subjects, see the [docs/](docs) directory.

### Build status

[![Testing](https://github.com/puppetlabs/vmpooler/actions/workflows/testing.yml/badge.svg)](https://github.com/puppetlabs/vmpooler/actions/workflows/testing.yml)

## License

VMPooler is distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).  See the [LICENSE](LICENSE) file for more details.
