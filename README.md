![VMPooler](lib/vmpooler/public/img/logo.png)

# VMPooler

VMPooler provides configurable 'pools' of instantly-available (pre-provisioned) and/or on-demand (provisioned on request) virtual machines.

## Usage

At [Puppet, Inc.](http://puppet.com) we run acceptance tests on thousands of disposable VMs every day. VMPooler manages the life cycle of these VMs from request through deletion, with options available to pool ready instances, and provision on demand.

The recommended method for deploying VMPooler is via [https://github.com/puppetlabs/vmpooler-deployment](vmpooler-deployment).

### Migrating to v3

Starting with the v3.x release, management of DNS records is implemented as DNS plugins, similar to compute providers. This means each pool configuration should be pointing to a configuration object in `:dns_config` to determine it's method of record management.

For those using the global `DOMAIN` environment variable or global `:config.domain` key, this means records were not previously being managed by VMPooler (presumably managed via dynamic dns), so it's value should be moved to `:dns_configs:<INSERT_YOUR_OWN_SYMBOL>:domain` with the value for `dns_class` for the config set to `dynamic-dns`.

For example, the following < v3.x configuration:

```yaml
:config:
  domain: 'example.com'
```

becomes:

```yaml
:dns_configs:
  :example:
    dns_class: dynamic-dns
    domain: 'example.com'
```

Then any pools that should have records created via the dns config above should now reference the named dns config in the `dns_plugin` key:

```yaml
:pools:
  - name: 'debian-8-x86_64'
    dns_plugin: 'example'
```

For those using the GCE provider, [vmpooler-provider-gce](https://github.com/puppetlabs/vmpooler-provider-gce), as of version 1.x the DNS management has been decoupled. See <https://github.com/puppetlabs/vmpooler-provider-gce#migrating-to-v1>

### v2.0.0 note

As of version 2.0.0, all providers other than the dummy one are now separate gems. Historically the vSphere provider was included within VMPooler itself. That code has been moved to the [puppetlabs/vmpooler-provider-vsphere](https://github.com/puppetlabs/vmpooler-provider-vsphere) repository and the `vmpooler-provider-vsphere` gem. To migrate from VMPooler 1.x to 2.0 you will need to ensure that `vmpooler-provider-vsphere` is installed along side the `vmpooler` gem. See the  [Provider API](docs/PROVIDER_API.md) docs for more information.

## Installation

The recommended method of installation is via the Helm chart located in [puppetlabs/vmpooler-deployment](https://github.com/puppetlabs/vmpooler-deployment). That repository also provides Docker images of VMPooler.

### Dependencies

#### Redis

VMPooler requires a [Redis](http://redis.io/) server. This is the data store used for VMPooler's inventory and queuing services.

#### Other gems

VMPooler itself and the dev environment talked about below require additional Ruby gems to function. You can update the currently required ones for VMPooler by running `./update-gemfile-lock.sh`. The gems for the dev environment can be updated by running `./docker/update-gemfile-lock.sh`. These scripts will utilize the container on the FROM line of the Dockerfile to update the Gemfile.lock in the root of this repo and in the docker folder, respectively.

## Configuration

Configuration for VMPooler may be provided via environment variables, or a configuration file.

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

## Components

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

## Development

### docker-compose

A docker-compose file is provided to support running VMPooler and associated tools locally. This is useful for development because your local code is used to build the gem used in the docker-compose environment. The compose environment also pulls in the latest providers via git. Details of this setup are stored in the `docker/` folder.

```bash
docker-compose -f docker/docker-compose.yml build && \
docker-compose -f docker/docker-compose.yml up
```

### Running docker-compose inside Vagrant

A Vagrantfile is included in this repository so as to provide a reproducible development environment.

```bash
vagrant up
vagrant ssh
cd /vagrant
docker-compose -f docker/docker-compose.yml build && \
docker-compose -f docker/docker-compose.yml up
```

The Vagrant environment also contains multiple rubies you can utilize for spec test and the like. You can see a list of the pre-installed ones when you log in as part of the message of the day.

For more information about setting up a development instance of VMPooler or other subjects, see the [docs/](docs) directory.

### URLs when using docker-compose

| Endpoint          | URL                                                                   |
|-------------------|-----------------------------------------------------------------------|
| Redis Commander   | [http://localhost:8079](http://localhost:8079)                        |
| API               | [http://localhost:8080/api/v1]([http://localhost:8080/api/v1)         |
| Dashboard         | [http://localhost:8080/dashboard/](http://localhost:8080/dashboard/)  |
| Metrics (API)     | [http://localhost:8080/prometheus]([http://localhost:8080/prometheus) |
| Metrics (Manager) | [http://localhost:8081/prometheus]([http://localhost:8081/prometheus) |
| Jaeger            | [http://localhost:8082](http://localhost:8082)                        |

Additionally, the Redis instance can be accessed at `localhost:6379`.

## Update the Gemfile Lock

To update the `Gemfile.lock` run `./update-gemfile-lock`.

Verify, and update if needed, that the docker tag in the script and GitHub action workflows matches what is used in the [vmpooler-deployment Dockerfile](https://github.com/puppetlabs/vmpooler-deployment/blob/main/docker/Dockerfile).

## Releasing

Follow these steps to publish a new GitHub release, and build and push the gem to <https://rubygems.org>.

1. Bump the "VERSION" in `lib/vmpooler/version.rb` appropriately based on changes in `CHANGELOG.md` since the last release.
2. Run `./release-prep` to update `Gemfile.lock` and `CHANGELOG.md`.
3. Commit and push changes to a new branch, then open a pull request against `main` and be sure to add the "maintenance" label.
4. After the pull request is approved and merged, then navigate to Actions --> Release Gem --> run workflow --> Branch: main --> Run workflow.

## License

VMPooler is distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).  See the [LICENSE](LICENSE) file for more details.
