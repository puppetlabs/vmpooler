# Table of contents
1. [API](#API)
2. [Token operations](#token)
3. [VM operations](#vmops)
4. [Add disks](#adddisks)
5. [VM snapshots](#vmsnapshots)
6. [Status and metrics](#statusmetrics)
7. [Pool configuration](#poolconfig)
8. [Ondemand VM provisioning](#ondemandvm)

### API <a name="API"></a>

vmpooler provides a REST API for VM management.  The following examples use `curl` for communication.

## Major change in V3 versus V2

The api/v1 and api/v2 endpoints have been removed. Additionally, the generic api endpoint that reroutes to a versioned endpoint has been removed.

The api/v3 endpoint removes the deprecated "domain" key returned in some of the operations like getting a VM, etc. If there is a "domain" configured in the top level configuration or for a specific provider,
the hostname now returns an FQDN including that domain. That is to say, we can now have multiple, different domains for each pool instead of only a single domain for all pools, or a domain restricted to a particular provider.

Clients using some of the direct API paths (without specifying api/v1 or api/v2) will now now need to specify the versioned endpoint (api/v3).

## Major change in V2 versus V1

The api/v2 endpoint removes a separate "domain" key returned in some of the operations like getting a VM, etc. If there is a "domain" configured in the top level configuration or for a specific provider,
the hostname now returns an FQDN including that domain. That is to say, we can now have multiple, different domains for each provider instead of only one.

Clients using some of the direct API paths (without specifying api/v1 or api/v2) will still be redirected to v1, but this behavior is notw deprecated and will be changed to v2 in the next major version.

### updavig clients from v1 to v2

Clients need to update their paths to using api/v2 instead of api/v1. Please note the API responses that used to return a "domain" key, will no longer have a separate "domain" key and now return
the FQDN (includes the domain in the hostname).

One way to support both v1 and v2 in the client logic is to look for a "domain" and append it to the hostname if it exists (existing v1 behavior). If the "domain" key does not exist, you can use the hostname 
as is since it is a FQDN (v2 behavor).

#### Token operations <a name="token"></a>

Token-based authentication can be used when requesting or modifying VMs.  The `/token` route can be used to create, query, or delete tokens.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), for information on configuring an authentication store to use when performing token operations.

##### GET /token

Get a list of issued tokens.

Return codes:
* 200  OK
* 401  when not authorized
* 404  when config:auth not found or other error

```
$ curl -u jdoe --url vmpooler.example.com/api/v3/token
Enter host password for user 'jdoe':
```
```json
{
    "ok": true,
    "utpg2i2xswor6h8ttjhu3d47z53yy47y": {
      "created": "2015-04-28 19:17:47 -0700"
    }
}
```

##### POST /token

Generate a new authentication token.

Return codes:
* 200  OK
* 401  when not authorized
* 404  when config:auth not found

```
$ curl -X POST -u jdoe --url vmpooler.example.com/api/v3/token
Enter host password for user 'jdoe':
```
```json
{
    "ok": true,
    "token": "utpg2i2xswor6h8ttjhu3d47z53yy47y"
}
```

##### GET /token/&lt;token&gt;

Get information about an existing token (including associated VMs).

Return codes:
* 200  OK
* 404  when config:auth or token not found

```
$ curl --url vmpooler.example.com/api/v3/token/utpg2i2xswor6h8ttjhu3d47z53yy47y
```
```json
{
  "ok": true,
  "utpg2i2xswor6h8ttjhu3d47z53yy47y": {
    "user": "jdoe",
    "created": "2015-04-28 19:17:47 -0700",
    "last": "2015-11-04 12:28:37 -0700",
    "vms": {
      "running": [
        "dqs4914g2wjyy5w",
        "hul7ib0ssr0f4o0"
      ]
    }
  }
}
```

##### DELETE /token/&lt;token&gt;

Delete an authentication token.

Return codes:
* 200  OK
* 401  when not authorized
* 404  when config:auth not found

```
$ curl -X DELETE -u jdoe --url vmpooler.example.com/api/v3/token/utpg2i2xswor6h8ttjhu3d47z53yy47y
Enter host password for user 'jdoe':
```
```json
{
  "ok": true
}
```

#### VM operations <a name="vmops"></a>

##### GET /vm

Retrieve a list of available VM pools.

Return codes:
* 200  OK

```
$ curl --url vmpooler.example.com/api/v3/vm
```
```json
[
  "debian-7-i386",
  "debian-7-x86_64"
]
```

##### POST /vm

Useful for batch operations; post JSON (see format below), get back allocated VMs.

If an authentication store is configured, an authentication token supplied via the `X-AUTH-TOKEN` HTTP header will modify a VM's default lifetime.  See the provided YAML configuration example, [vmpooler.yaml.example](vmpooler.yaml.example), and the 'token operations' section above for more information.

Return codes:
* 200  OK
* 404  when sending invalid JSON in the request body or requesting an invalid VM pool name
* 503  when the vm failed to allocate a vm, or the pool is empty

```
$ curl -d '{"debian-7-i386":"2","debian-7-x86_64":"1"}' --url vmpooler.example.com/api/v3/vm
```
```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": [
      "o41xtodlvnvu5cw.example.com",
      "khirruvwfjlmx3y.example.com"
    ]
  },
  "debian-7-x86_64": {
    "hostname": "y91qbrpbfj6d13q.example.com"
  }
}
```

**NOTE: Returns either all requested VMs or no VMs.**

##### POST /vm/&lt;pool&gt;

Check-out a VM or VMs.

Return codes:
* 200  OK
* 404  when sending invalid JSON in the request body or requesting an invalid VM pool name
* 503  when the vm failed to allocate a vm, or the pool is empty

```
$ curl -d --url vmpooler.example.com/api/v3/vm/debian-7-i386
```
```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": "fq6qlpjlsskycq6.example.com"
  }
}
```

Multiple VMs can be requested by using multiple query parameters in the URL:

```
$ curl -d --url vmpooler.example.com/api/v3/vm/debian-7-i386+debian-7-i386+debian-7-x86_64
```

```json
{
  "ok": true,
  "debian-7-i386": {
    "hostname": [
      "sc0o4xqtodlul5w.example.com",
      "4m4dkhqiufnjmxy.example.com"
    ]
  },
  "debian-7-x86_64": {
    "hostname": "zb91y9qbrbf6d3q.example.com"
  }
}
```

**NOTE: Returns either all requested VMs or no VMs.**

##### GET /vm/&lt;hostname&gt;

Query metadata information for a checked-out VM.

Return codes:
* 200  OK
* 404  when requesting an invalid VM hostname

```
$ curl --url vmpooler.example.com/api/v3/vm/pxpmtoonx7fiqg6
```
```json
{
  "ok": true,
  "pxpmtoonx7fiqg6": {
    "template": "centos-6-x86_64",
    "lifetime": 12,
    "running": 3,
    "remaining": 9, 
    "state": "running",
    "tags": {
      "department": "engineering",
      "user": "jdoe"
    },
    "ip": "192.168.0.1",
    "host": "host1.example.com",
    "migrated": "true"
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

Return codes:
* 200  OK
* 401  when you need an auth token
* 404  when requesting an invalid VM hostname
* 400  when supplied PUT parameters fail validation

```
$ curl -X PUT -d '{"lifetime":"2"}' --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

```
$ curl -X PUT -d '{"tags":{"department":"engineering","user":"jdoe"}}' --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

##### DELETE /vm/&lt;hostname&gt;

Schedule a checked-out VM for deletion.

Return codes:
* 200  OK
* 401  when you need an auth token
* 404  when requesting an invalid VM hostname

```
$ curl -X DELETE --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6
```
```json
{
  "ok": true
}
```

#### Adding additional disk(s) <a name="adddisks"></a>

##### POST /vm/&lt;hostname&gt;/disk/&lt;size&gt;

Add an additional disk to a running VM.

Return codes:
* 202  OK
* 401  when you need an auth token
* 404  when requesting an invalid VM hostname or size is not an integer

````
$ curl -X POST -H X-AUTH-TOKEN:a9znth9dn01t416hrguu56ze37t790bl --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6/disk/8
````
````json
{
  "ok": true,
  "fq6qlpjlsskycq6": {
    "disk": "+8gb"
  }
}
````

Provisioning and attaching disks can take a moment, but once the task completes it will be reflected in a `GET /vm/<hostname>` query:

````
$ curl --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6
````
````json
{
  "ok": true,
  "fq6qlpjlsskycq6": {
    "template": "debian-7-x86_64",
    "lifetime": 2,
    "running": 0.08,
    "state": "running",
    "disk": [
      "+8gb"
    ]
  }
}

````

#### VM snapshots <a name="vmsnapshots"></a>

##### POST /vm/&lt;hostname&gt;/snapshot

Create a snapshot of a running VM.

Return codes:
* 202  OK
* 401  when you need an auth token
* 404  when requesting an invalid VM hostname

````
$ curl -X POST -H X-AUTH-TOKEN:a9znth9dn01t416hrguu56ze37t790bl --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6/snapshot
````
````json
{
  "ok": true,
  "fq6qlpjlsskycq6": {
    "snapshot": "n4eb4kdtp7rwv4x158366vd9jhac8btq"
  }
}
````

Snapshotting a live VM can take a moment, but once the snapshot task completes it will be reflected in a `GET /vm/<hostname>` query:

````
$ curl --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6
````
````json
{
  "ok": true,
  "fq6qlpjlsskycq6": {
    "template": "debian-7-x86_64",
    "lifetime": 2,
    "running": 0.08,
    "state": "running",
    "snapshots": [
      "n4eb4kdtp7rwv4x158366vd9jhac8btq"
    ]
  }
}
````

##### POST /vm/&lt;hostname&gt;/snapshot/&lt;snapshot&gt;

Revert a VM back to a snapshot.

Return codes:
* 202  OK
* 401  when you need an auth token
* 404  when requesting an invalid VM hostname or snapshot is not valid

````
$ curl X POST -H X-AUTH-TOKEN:a9znth9dn01t416hrguu56ze37t790bl --url vmpooler.example.com/api/v3/vm/fq6qlpjlsskycq6/snapshot/n4eb4kdtp7rwv4x158366vd9jhac8btq
````
````json
{
  "ok": true
}
````

#### Status and metrics <a name="statusmetrics"></a>

##### GET /status

A "live" status endpoint, representing the current state of the service.

```
$ curl --url vmpooler.example.com/api/v3/status
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

The top level sections are: "capacity", "queue", "clone", "boot", "pools" and "status".
If the query parameter 'view' is provided, it will be used to select which top level
element to compute and return. Select them by specifying which one you want in a comma 
separated list.
For example `vmpooler.example.com/api/v3/status?view=capacity,boot`

##### GET /summary[?from=YYYY-MM-DD[&to=YYYY-MM-DD]]

Returns a summary, or report, for the timespan between `from` and `to` (inclusive)
parameters. The response includes both an overall and daily view of tracked
metrics, such as boot and cloning durations.

Any omitted query parameter will default to now/today. A request without any
parameters will result in the current day's summary.

Return codes:
* 200  OK
* 400  Invalid date format or range


```
$ curl --url vmpooler.example.com/api/v3/summary
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
  "tag": {
    "department": {
      "engineering": 14,
      "help desk": 10,
      "IT": 44,
      "total": 68
    },
    "user": {
      "arodgers": 54,
      "cmatthews": 10,
      "jnelson": 4,
      "total": 68
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
      },
      "tag": {
        "department": {
          "engineering": 14,
          "help desk": 10,
          "IT": 44,
          "total": 68
        },
        "user": {
          "arodgers": 54,
          "cmatthews": 10,
          "jnelson": 4,
          "total": 68
        }
      }
    }
  ]
}
```


```
$ curl -G -d 'from=2015-03-10' -d 'to=2015-03-11' --url vmpooler.example.com/api/v3/summary
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
      },
      "tag": { }
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
      },
      "tag": { }
    }
  ]
}
```

You can also query only the specific top level section you want by including it after `summary/`.
The valid sections are "boot", "clone" or "tag" eg. `vmpooler.example.com/api/v3/summary/boot/`.
You can further drill-down the data by specifying the second level parameter to query eg
`vmpooler.example.com/api/v3/summary/tag/created_by`

##### GET /poolstat?pool=FOO

For parameter `pool`, containing a comma separated list of pool names to query, this endpoint returns
each of the pool's ready, max and alias information. It can be used to get a fast response for
the required pools instead of using the /status API endpoint

Return codes
* 200  OK 

```
$ curl https://vmpooler.example.com/api/v3/poolstat?pool=centos-6-x86_64
```
```json
{
  "pools": {
    "centos-6-x86_64": {
      "ready": 25,
      "max": 25,
      "alias": [
        "centos-6-64",
        "centos-6-amd64"
      ]
    }
  }
}
```

##### GET /totalrunning

Fast endpoint to return the total number of VMs in a 'running' state

Return codes
* 200  OK 

```
$ curl https://vmpooler.example.com/api/v3/totalrunning
```

```json
{

  "running": 362

}
```

#### Managing pool configuration via API <a name="poolconfig"></a>

##### GET /config

Returns the running pool configuration

Return codes
* 200  OK 
* 400  No configuration found  

```
$ curl https://vmpooler.example.com/api/v3/config
```
```json
{
  "pool_configuration": [
    {
      "name": "redhat-7-x86_64",
      "template": "templates/redhat-7.2-x86_64-0.0.3",
      "folder": "vmpooler/redhat-7-x86_64",
      "datastore": "stor1",
      "size": 1,
      "datacenter": "dc1",
      "provider": "vsphere",
      "capacity": 1,
      "major": "redhat",
      "template_ready": true
    }
  ],
  "status": {
    "ok": true
  }
}
```

Note: to enable poolsize and pooltemplate config endpoints it is necessary to set 'experimental_features: true' in your vmpooler configuration. A 405 is returned when you attempt to interact with these endpoints when this configuration option is not set.

##### POST /config/poolsize

Change pool size without having to restart the service.

All pool template changes requested must be for pools that exist in the vmpooler configuration running, or a 404 code will be returned

When a pool size is changed due to the configuration posted a 201 status will be returned. When the pool configuration is valid, but will not result in any changes, 200 is returned.

Pool size configuration changes persist through application restarts, and take precedence over a pool size value configured in the pool configuration provided when the application starts. This persistence is dependent on redis. So, if the redis data is lost then the configuration updates revert to those provided at startup at the next application start.

An authentication token is required in order to change pool configuration when authentication is configured.
Responses:
* 200 - No changes required
* 201 - Changes made on at least one pool with changes requested
* 400 - An invalid configuration was provided causing requested changes to fail
* 404 - An unknown error occurred
* 405 - The endpoint is disabled because experimental features are disabled
```
$ curl -X POST -H "Content-Type: application/json" -d '{"debian-7-i386":"2","debian-7-x86_64":"1"}' --url https://vmpooler.example.com/api/v3/config/poolsize
```
```json
{
  "ok": true
}
```

##### DELETE /config/poolsize/&lt;pool&gt;

Delete an overridden pool size. This results in the values from VMPooler's config being used.

Return codes:
* 200 - when nothing was changed but no error occurred
* 201 - size reset successful
* 401 - when not authorized
* 404 - pool does not exist
* 405 - The endpoint is disabled because experimental features are disabled

```
$ curl -X DELETE -u jdoe --url vmpooler.example.com/api/v3/poolsize/almalinux-8-x86_64
```
```json
{
    "ok": true,
    "pool_size_before_overrides": 2,
    "pool_size_before_reset": 4
}
```

##### POST /config/pooltemplate

Change the template configured for a pool, and replenish the pool with instances built from the new template.

All pool template changes requested must be for pools that exist in the vmpooler configuration running, or a 404 code will be returned

When a pool template is changed due to the configuration posted a 201 status will be returned. When the pool configuration is valid, but will not result in any changes, 200 is returned.

A pool template being updated will cause the following actions, which are logged in vmpooler.log:
* Destroy all instances for the pool template being updated that are in the ready and pending state
* Halt repopulating the pool while creating template deltas for the newly configured template
* Unblock pool population and let the pool replenish with instances based on the newly configured template

Pool template changes persist through application restarts, and take precedence over a pool template configured in the pool configuration provided when the application starts. This persistence is dependent on redis. As a result, if the redis data is lost then the configuration values revert to those provided at startup at the next application start.

An authentication token is required in order to change pool configuration when authentication is configured.

Responses:
* 200 - No changes required
* 201 - Changes made on at least one pool with changes requested
* 400 - An invalid configuration was provided causing requested changes to fail
* 404 - An unknown error occurred
* 405 - The endpoint is disabled because experimental features are disabled
```
$ curl -X POST -H "Content-Type: application/json" -d '{"debian-7-i386":"templates/debian-7-i386"}' --url https://vmpooler.example.com/api/v3/config/pooltemplate
```
```json
{
  "ok": true
}
```

##### DELETE /config/pooltemplate/&lt;pool&gt;

Delete an overridden pool template. This results in the values from VMPooler's config being used.

Return codes:
* 200 - when nothing was changed but no error occurred
* 201 - template reset successful
* 401 - when not authorized
* 404 - pool does not exist
* 405 - The endpoint is disabled because experimental features are disabled

```
$ curl -X DELETE -u jdoe --url vmpooler.example.com/api/v3/pooltemplate/almalinux-8-x86_64
```
```json
{
    "ok": true,
    "template_before_overrides": "templates/almalinux-8-x86_64-0.0.2",
    "template_before_reset": "templates/almalinux-8-x86_64-0.0.3-beta"
}
```

##### POST /poolreset

Clear all pending and ready instances in a pool, and deploy replacements

All pool reset requests must be for pools that exist in the vmpooler configuration running, or a 404 code will be returned.

When a pool reset is requested a 201 status will be returned.

A pool reset will cause vmpooler manager to log that it has cleared ready and pending instances.

For poolreset to be available it is necessary to enable experimental features. Additionally, the request must be performed with an authentication token when authentication is configured.

Responses:
* 201 - Pool reset requested received
* 400 - An invalid configuration was provided causing requested changes to fail
* 404 - An unknown error occurred
* 405 - The endpoint is disabled because experimental features are disabled
```
$ curl -X POST -H "Content-Type: application/json" -d '{"debian-7-i386":"1"}' --url https://vmpooler.example.com/api/v3/poolreset
```
```json
{
  "ok": true
}
```

#### Ondemand VM operations <a name="ondemandvm"></a>

Ondemand VM operations offer a user an option to directly request instances to be allocated for use. This can be very useful when supporting a wide range of images because idle instances can be eliminated.

##### POST /ondemandvm

All instance types requested must match a pool name or alias in the running application configuration, or a 404 code will be returned

When a provisioning request is accepted the API will return an indication that the request is successful. You may then poll /ondemandvm to monitor request status.

An authentication token is required in order to request instances on demand when authentication is configured.

Responses:
* 201 - Provisioning request accepted
* 400 - Payload contains invalid JSON and cannot be parsed
* 401 - No auth token provided, or provided auth token is not valid, and auth is enabled
* 403 - Request exceeds the configured per pool maximum
* 404 - A pool was requested, which is not available in the running configuration, or an unknown error occurred.
* 409 - A request of the matching ID has already been created
```
$ curl -X POST -H "Content-Type: application/json" -d '{"debian-7-i386":"4"}' --url https://vmpooler.example.com/api/v3/ondemandvm
```
```json
{
  "ok": true,
  "request_id": "e3ff6271-d201-4f31-a315-d17f4e15863a"
}
```

##### GET /ondemandvm

Get the status of an ondemandvm request that has already been posted.

When the request is ready the ready status will change to 'true'.

The number of instances pending vs ready will be reflected in the API response.

Responses:
* 200 - The API request was successful and the status is ok
* 202 - The request is not ready yet
* 404 - The request can not be found, or an unknown error occurred
```
$ curl https://vmpooler.example.com/api/v3/ondemandvm/e3ff6271-d201-4f31-a315-d17f4e15863a
```
```json
{
  "ok": true,
  "request_id": "e3ff6271-d201-4f31-a315-d17f4e15863a",
  "ready": false,
  "debian-7-i386": {
    "ready": "3",
    "pending": "1"
  }
}
```
```json
{
  "ok": true,
  "request_id": "e3ff6271-d201-4f31-a315-d17f4e15863a",
  "ready": true,
  "debian-7-i386": {
    "hostname": [
      "vm1",
      "vm2",
      "vm3",
      "vm4"
    ]
  }
}
```

##### DELETE /ondemandvm

Delete a ondemand request

Deleting a ondemand request will delete any instances created for the request and mark the backend data for expiration in two weeks. Any subsequent attempts to retrieve request data will indicate it has been deleted.

Responses:
* 200 - The API request was sucessful. A message will indicate if the request has already been deleted.
* 401 - No auth token provided, or provided auth token is not valid, and auth is enabled
* 404 - The request can not be found, or an unknown error occurred.
```
$ curl -X DELETE https://vmpooler.example.com/api/v3/ondemandvm/e3ff6271-d201-4f31-a315-d17f4e15863a
```
```json
{
  "ok": true
}
```
