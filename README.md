![vmpooler](https://raw.github.com/sschneid/vmpooler/master/lib/vmpooler/public/img/logo.gif)

# vmpooler

vmpooler provides configurable 'pools' of available (running) virtual machines.


## Usage

At [Puppet Labs](http://puppetlabs.com) we run acceptance tests on thousands of disposable VMs every day.  Dynamic cloning of VM templates initially worked fine for this, but added several seconds to each test run and was unable to account for failed clone tasks.  By pushing these operations to a backend service, we were able to both speed up tests and eliminate test failures due to underlying infrastructure failures.


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

#### Token operations

Token-based authentication can be used when requesting or modifying VMs.  The `/token` route can be used to create, query, or delete tokens.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for information on configuring an authentication store to use when performing token operations.

##### GET /token/&lt;token&gt;

Get information about an existing token.

```
$ curl -u sschneid --url vmpooler.company.com/token/utpg2i2xswor6h8ttjhu3d47z53yy47y
Enter host password for user 'sschneid':
```
```json
{
  "ok": true,
  "utpg2i2xswor6h8ttjhu3d47z53yy47y": {
    "user": "sschneid",
    "timestamp": "2015-04-28 19:17:47 -0700"
  }
}
```

##### POST /token

Generate a new authentication token.

```
$ curl -X POST -u sschneid --url vmpooler.company.com/token
Enter host password for user 'sschneid':
```
```json
{
    "ok": true,
    "token": "utpg2i2xswor6h8ttjhu3d47z53yy47y"
}
```

##### DELETE /token/&lt;token&gt;

Delete an authentication token.

```
$ curl -X DELETE -u sschneid --url vmpooler.company.com/token/utpg2i2xswor6h8ttjhu3d47z53yy47y
Enter host password for user 'sschneid':
```
```json
{
  "ok": true
}
```

#### VM operations

##### GET /vm

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

##### POST /vm

Useful for batch operations; post JSON (see format below), get back VMs.

If an authentication store is configured, an authentication token supplied via the `X-AUTH-TOKEN` HTTP header will modify a VM's default lifetime.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), and the 'token operations' section above for more information.

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

##### POST /vm/&lt;pool&gt;

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

##### GET /vm/&lt;hostname&gt;

Query a checked-out VM.

```
$ curl --url vmpooler.company.com/vm/pxpmtoonx7fiqg6
```
```json
{
  "ok": true,
  "pxpmtoonx7fiqg6": {
    "template": "centos-6-x86_64",
    "lifetime": 12,
    "running": 3,
    "domain": "company.com"
  }
}
```

##### PUT /vm/&lt;hostname&gt;

Modify a checked-out VM.

The following are valid PUT parameters and their required data structures:

parameter | description | required structure
--------- | ----------- | ------------------
*lifetime* | VM TTL (in hours) | integer
*tags* | free-form VM tagging | hash

Any modifications can be verified using the [GET /vm/&lt;hostname&gt;](#get-vmhostname) endpoint.

If an authentication store is configured, an authentication token is required (via the `X-AUTH-TOKEN` HTTP header) to access this route.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), and the 'token operations' section above for more information.

```
$ curl -X PUT -d '{"lifetime":"2"}' --url vmpooler.company.com/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

```
$ curl -X PUT -d '{"tags":{"department":"engineering","user":"sschneid"}}' --url vmpooler.company.com/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

##### DELETE /vm/&lt;hostname&gt;

Schedule a checked-out VM for deletion.

```
$ curl -X DELETE --url vmpooler.company.com/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

#### Status and metrics

##### GET /status

A "live" status endpoint, representing the current state of the service.

```
$ curl --url vmpooler.company.com/status
```
```json
{
  "capacity": {
    "current": 716,
    "total": 717,
    "percent": 99.9
  },
  "clone": {
    "duration": {
      "average": 8.8,
      "min": 2.79,
      "max": 69.76
    },
    "count": {
      "total": 1779
    }
  },
  "queue": {
    "pending": 1,
    "cloning": 0,
    "booting": 1,
    "ready": 716,
    "running": 142,
    "completed": 0,
    "total": 859
  },
  "status": {
    "ok": true,
    "message": "Battle station fully armed and operational."
  }
}
```

If there are empty pools, the "status" section will convey this:

```json
  "status": {
    "ok": false,
    "message": "Found 2 empty pools.",
    "empty": [
      "centos-6-x86_64",
      "debian-7-x86_64"
    ]
  }
```

##### GET /summary[?from=YYYY-MM-DD[&to=YYYY-MM-DD]]

Returns a summary, or report, for the timespan between `from` and `to` (inclusive)
parameters. The response includes both an overall and daily view of tracked
metrics, such as boot and cloning durations.

Any omitted query parameter will default to now/today. A request without any
parameters will result in the current day's summary.

```
$ curl --url vmpooler.company.com/summary
```
```json
{
  "boot": {
    "duration": {
      "average": 106.6,
      "min": 83.09,
      "max": 121.06,
      "total": 639.36,
    },
    "count": {
      "average": 6,
      "min": 6,
      "max": 6,
      "total": 6,
    }
  },
  "clone": {
    "duration": {
      "average": 4.6,
      "min": 2.78,
      "max": 8.1,
      "total": 63.94,
    },
    "count": {
      "average": 14,
      "min": 14,
      "max": 14,
      "total": 14,
    }
  },
  "daily": [
    {
      "date": "2015-03-11",
      "boot": {
        "duration": {
          "average": 106.6,
          "min": 83.09,
          "max": 121.06,
          "total": 639.36
        },
        "count": {
          "total": 6
        }
      },
      "clone": {
        "duration": {
          "average": 4.6,
          "min": 2.78,
          "max": 8.1,
          "total": 63.94
        },
        "count": {
          "total": 14
        }
      }
    }
  ]
}
```

```
$ curl -G -d 'from=2015-03-10' -d 'to=2015-03-11' --url vmpooler.company.com/summary
```
```json
{
  "boot": {...},
  "clone": {...},
  "daily": [
    {
      "date": "2015-03-10",
      "boot": {
        "duration": {
          "average": 0,
          "min": 0,
          "max": 0,
          "total": 0
        },
        "count": {
          "total": 0
        }
      },
      "clone": {
        "duration": {
          "average": 0,
          "min": 0,
          "max": 0,
          "total": 0
        },
        "count": {
          "total": 0
        }
      }
    },
    {
      "date": "2015-03-11",
      "boot": {
        "duration": {
          "average": 106.6,
          "min": 83.09,
          "max": 121.06,
          "total": 639.36
        },
        "count": {
          "total": 6
        }
      },
      "clone": {
        "duration": {
          "average": 4.6,
          "min": 2.78,
          "max": 8.1,
          "total": 63.94
        },
        "count": {
          "total": 14
        }
      }
    }
  ]
}
```

### Dashboard

A dashboard is provided to offer real-time statistics and historical graphs.  It looks like this in a large installation on a fairly busy day:

![dashboard](https://raw.github.com/sschneid/vmpooler/gh-pages/img/screenshots/dashboard.png)

[Graphite](http://graphite.wikidot.com/) is required for historical data retrieval.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for details.


## License

vmpooler is distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).  See the [LICENSE](LICENSE) file for more details.
