# Configuring vmpooler

Vmpooler configuration can be provided via file or environment variable. Some configuration elements are unique to API or manager components. This document aims to describe options for providing vmpooler configuration via environment variables.

# Table of contents
1. [Global options](#global)
2. [Manager specific options](#manager)
3. [API specific options](#API)

## Global options <a name="global"></a>

These options affect manager and API applications.

### VMPOOLER\_CONFIG

Provide the entire configuration as a blob of yaml. Individual parameters passed via environment variable will override any setting in this blob, or a configuration file passed in.

### VMPOOLER\_CONFIG\_FILE

Path to a the file to use when loading the vmpooler configuration. This is only evaluated if `VMPOOLER_CONFIG` has not been specified.

### DOMAIN

If set, returns a top-level 'domain' JSON key in POST requests
(optional)

### REDIS\_SERVER

The redis server to use for vmpooler.
(optional; default: 'localhost')

### REDIS\_PORT

The port to use when connecting to redis.
(optional)

### REDIS\_PASSWORD

The password to use when connecting to redis.
(optional)

### REDIS\_DATA\_TTL

How long to keep data when set to expire in hours.
(optional; default: 168)

### STATSD\_SERVER

The FQDN hostname of the statsd daemon.
(optional)

### STATSD\_PREFIX

The prefix to use while storing statsd data.
(optional; default: 'vmpooler')

### STATSD\_PORT

The UDP port to communicate with the statsd daemon.
(optional; default: 8125)

### GRAPHITE\_SERVER

The FQDN hostname of the Graphite server.
(optional)

### GRAPHITE\_PREFIX

The prefix to use while storing Graphite data.
(optional; default: 'vmpooler')

### GRAPHITE\_PORT

The TCP port to communicate with the graphite server.
(optional; default: 2003)

### MAX\_ONDEMAND\_INSTANCES\_PER\_REQUEST

The maximum number of instances any individual ondemand request may contain per pool.
(default: 10)

### ONDEMAND\_REQUEST\_TTL

The amount of time (in minutes) to give for a ondemand request to be fulfilled before considering it to have failed.
(default: 5)

## Manager options <a name="manager"></a>

### TASK\_LIMIT

The number of concurrent VM creation tasks to perform. Only affects manager.
(optional; default: 10)

### MIGRATION\_LIMIT

When set to any value greater than 0 enable VM migration at checkout.
When enabled this capability will evaluate a VM for migration to a different host when it is requested in an effort to maintain a more even distribution of load across compute resources. The number of migrations in progress at any one time are constrained by this value.
(optional)

### VM\_CHECKTIME

How often (in minutes) to check the sanity of VMs in 'ready' queues.
(optional; default: 15)

### VM\_LIFETIME

How long (in hours) to keep VMs in 'running' queues before destroying.
(optional; default: 24)

### VM\_LIFETIME\_AUTH

Same as `vm_lifetime`, but applied if a valid authentication token is
included during the request.
(required)

### PREFIX

If set, prefixes all created VMs with this string. This should include a separator.
(optional; default: '')

### LOGFILE

The file to use for logging manager operations.
(optional; default: '/var/log/vmpooler.log')

### CLONE\_TARGET

The target cluster VMs are cloned into (host with least VMs chosen)
(optional; default: same cluster/host as origin template)

### TIMEOUT

How long (in minutes) before marking a clone as 'failed' and retrying.
(optional; default: 15)

### READY\_TTL

How long (in minutes) a ready VM should stay in the ready queue.
(default: 60)

### MAX\_TRIES

Set the max number of times a connection should retry in VM providers. This optional setting allows a user to dial in retry limits to suit your environment.
(optional; default: 3)

### RETRY\_FACTOR

When retrying, each attempt sleeps for the try count * retry\_factor.
Increase this number to lengthen the delay between retry attempts.
This is particularly useful for instances with a large number of pools
to prevent a thundering herd when retrying connections.
(optional; default: 10)

### CREATE\_FOLDERS

Create the pool folder specified in the pool configuration.
Note: this will only create the last folder when it does not exist. It will not create any parent folders.
(optional; default: false)

### CREATE\_TEMPLATE\_DELTA\_DISKS

Create backing delta disks for the specified templates to support creating linked clones.
(optional; default: false)

### CREATE\_LINKED\_CLONES

Whether to create linked clone virtual machines when using the vsphere provider.
This can also be set per pool.
(optional; default: true)

### PURGE\_UNCONFIGURED\_FOLDERS

Enable purging of VMs and folders detected within the base folder path that are not configured for the provider
Only a single layer of folders and their child VMs are evaluated from detected base folder paths
A base folder path for 'vmpooler/redhat-7' would be 'vmpooler'
When enabled in the global configuration then purging is enabled for all providers
Expects a boolean value
(optional; default: false)

### USAGE\_STATS

Enable shipping of VM usage stats
When enabled a metric is emitted when a machine is destroyed. Tags are inspected and used to organize
shipped metrics if there is a jenkins\_build\_url tag set for the VM.
Without the jenkins\_build\_url tag set the metric will be sent as "usage.$user.$pool\_name".
When the jenkins\_build\_url tag is set the metric will be sent with additional data. Here is an example
based off of the following URL;
https://jenkins.example.com/job/platform\_puppet-agent-extra\_puppet-agent-integration-suite\_pr/RMM\_COMPONENT\_TO\_TEST\_NAME=puppet,SLAVE\_LABEL=beaker,TEST\_TARGET=redhat7-64a/824/
"usage.$user.$instance.$value\_stream.$branch.$project.$job\_name.$component\_to\_test.$pool\_name", which translates to
"usage.$user.jenkins\_example\_com.platform.pr.puppet-agent-extra.puppet-agent-integration-suite.puppet.$pool\_name"
Expects a boolean value
(optional; default: false)

### EXTRA\_CONFIG

Specify additional application configuration files
The argument can accept a full path to a file, or multiple files comma separated.
Expects a string value
(optional)

### ONDEMAND\_CLONE\_LIMIT

Maximum number of simultaneous clones to perform for ondemand provisioning requests.
(default: 10)

### REDIS\_CONNECTION\_POOL\_SIZE

Maximum number of connections to utilize for the redis connection pool.
(default: 10)

### REDIS\_CONNECTION\_POOL\_TIMEOUT

How long a task should wait (in seconds) for a redis connection when all connections are in use.
(default: 5)

## API options <a name="API"></a>

### AUTH\_PROVIDER

The provider to use for authentication.
(optional)

### LDAP\_HOST

The FQDN hostname of the LDAP server.
(optional)

### LDAP\_PORT

The port used to connect to the LDAP service.
(optional; default: 389)

### LDAP\_BASE

The base DN used for LDAP searches.
This can be a string providing a single DN. For multiple DNs please specify the DNs as an array in a configuration file.
(optional)

### LDAP\_USER\_OBJECT

The LDAP object-type used to designate a user object.
(optional)

### SITE\_NAME

The name of your deployment.
(optional; default: 'vmpooler')

### EXPERIMENTAL\_FEATURES

Enable experimental API capabilities such as changing pool template and size without application restart
Expects a boolean value
(optional; default: false)

### MAX\_LIFETIME\_UPPER\_LIMIT

Specify a maximum lifetime that a VM may be extended to in hours.
(optional)
