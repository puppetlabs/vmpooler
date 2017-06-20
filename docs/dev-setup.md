# Setting up a vmpooler development environment

## Requirements

* Supported on OSX, Windows and Linux

* Ruby or JRuby

  Note - Ruby 1.x support will be removed so it is best to use more modern ruby versions

  Note - It is recommended to user Bundler instead of installing gems into the system repository

* A local Redis server

  Either a containerized instance of Redis or a local version is fine.

## Setup source and ruby

* Clone repository, either from your own fork or the original source

* Perform a bundle install

```
~/ > git clone https://github.com/puppetlabs/vmpooler.git
Cloning into 'vmpooler'...
remote: Counting objects: 3411, done.
...

~/ > cd vmpooler

~/vmpooler/ > bundle install
Fetching gem metadata from https://rubygems.org/.........
Fetching version metadata from https://rubygems.org/..
Resolving dependencies...
Installing rake 12.0.0
...
Bundle complete! 16 Gemfile dependencies, 37 gems now installed.
```

## Setup environment variables

### `VMPOOLER_DEBUG`

Setting the `VMPOOLER_DEBUG` environment variable will instruct vmpooler to:

* Output log messages to STDOUT

* Allow the use of the dummy authentication method

* Add interrupt traps so you can stop vmpooler when run interactively

Linux, OSX
```bash
~/vmpooler/ > export VMPOOLER_DEBUG=true
```

Windows (PowerShell)
```powershell
C:\vmpooler > $ENV:VMPOOLER_DEBUG = 'true'
```


### `VMPOOLER_CONFIG`

When `VMPOOLER_CONFIG` is set, vmpooler will read its configuration from the content of the environment variable instead of from the `vmpooler.yaml` configuration file.

Note that this variable does not point a different configuration file, but stores the contents of a configuration file.


## Setup vmpooler Configuration

You can either create a `vmpooler.yaml` file or set the `VMPOOLER_CONFIG` environment variable with the equivalent content.

Example minimal configuration file:
```yaml
---
:providers:
  :dummy:

:redis:
  server: 'localhost'

:auth:
   provider: dummy

:tagfilter:
  url: '(.*)\/'

:config:
  site_name: 'vmpooler'
  # Need to change this on Windows
  logfile: '/var/log/vmpooler.log'
  task_limit: 10
  timeout: 15
  vm_checktime: 15
  vm_lifetime: 12
  vm_lifetime_auth: 24
  allowed_tags:
    - 'created_by'
    - 'project'
  domain: 'company.com'
  prefix: 'poolvm-'

# Uncomment the lines below to suppress metrics to STDOUT
# :statsd:
#   server: 'localhost'
#   prefix: 'vmpooler'
#   port: 8125

:pools:
  - name: 'pool01'
    size: 5
    provider: dummy
  - name: 'pool02'
    size: 5
    provider: dummy
```

## Running vmpooler locally

* Run `bundle exec ruby vmpooler`

  If using JRuby, you may need to use `bundle exec jruby vmpooler`

You should see output similar to:
```
~/vmpooler/ > bundle exec ruby vmpooler
[2017-06-16 14:50:31] starting vmpooler
[2017-06-16 14:50:31] [!] Creating provider 'dummy'
[2017-06-16 14:50:31] [dummy] ConnPool - Creating a connection pool of size 1 with timeout 10
[2017-06-16 14:50:31] [*] [disk_manager] starting worker thread
[2017-06-16 14:50:31] [*] [snapshot_manager] starting worker thread
[2017-06-16 14:50:31] [*] [pool01] starting worker thread
[2017-06-16 14:50:31] [*] [pool02] starting worker thread
[2017-06-16 14:50:31] [dummy] ConnPool - Creating a connection object ID 1784
== Sinatra (v1.4.8) has taken the stage on 4567 for production with backup from Puma
*** SIGUSR2 not implemented, signal based restart unavailable!
*** SIGUSR1 not implemented, signal based restart unavailable!
*** SIGHUP not implemented, signal based logs reopening unavailable!
Puma starting in single mode...
* Version 3.9.1 (ruby 2.3.1-p112), codename: Private Caller
* Min threads: 0, max threads: 16
* Environment: development
* Listening on tcp://0.0.0.0:4567
Use Ctrl-C to stop
[2017-06-16 14:50:31] [!] [pool02] is empty
[2017-06-16 14:50:31] [!] [pool01] is empty
[2017-06-16 14:50:31] [ ] [pool02] Starting to clone 'poolvm-nexs1w50m4djap5'
[2017-06-16 14:50:31] [ ] [pool01] Starting to clone 'poolvm-r543eibo4b6tjer'
[2017-06-16 14:50:31] [ ] [pool01] Starting to clone 'poolvm-neqmu7wj7aukyjy'
[2017-06-16 14:50:31] [ ] [pool02] Starting to clone 'poolvm-nsdnrhhy22lnemo'
[2017-06-16 14:50:31] [ ] [pool01] 'poolvm-r543eibo4b6tjer' is being cloned from ''
[2017-06-16 14:50:31] [ ] [pool01] 'poolvm-neqmu7wj7aukyjy' is being cloned from ''
[2017-06-16 14:50:31] [ ] [pool02] 'poolvm-nexs1w50m4djap5' is being cloned from ''
[2017-06-16 14:50:31] [ ] [pool01] Starting to clone 'poolvm-edzlp954lyiozli'
[2017-06-16 14:50:31] [ ] [pool01] Starting to clone 'poolvm-nb0uci0yrwbxr6x'
[2017-06-16 14:50:31] [ ] [pool02] Starting to clone 'poolvm-y2yxgnovaneymvy'
[2017-06-16 14:50:31] [ ] [pool01] Starting to clone 'poolvm-nur59d25s1y8jko'
...
```

### Common Errors

* Forget to set VMPOOLER_DEBUG environment variable

vmpooler will fail to start with an error similar to below
```
~/vmpooler/ > bundle exec ruby vmpooler

~/vmpooler/lib/vmpooler.rb:44:in `config': Dummy authentication should not be used outside of debug mode; please set environment variable VMPOOLER_DEBUG to 'true' if you want to use dummy authentication (RuntimeError)
        from vmpooler:8:in `<main>'
...
```

* Error in vmpooler configuration

If there is an error in the vmpooler configuration file, or any other fatal error in the Pool Manager, vmpooler will appear to be running but no log information is displayed.  This is due to the error not being displayed until you press `Ctrl-C` and then suddenly you can see the cause of the issue.

For example, when running vmpooler on Windows, but with a unix style filename for the vmpooler log

```powershell
C:\vmpooler > bundle exec ruby vmpooler
[2017-06-16 14:49:57] starting vmpooler
== Sinatra (v1.4.8) has taken the stage on 4567 for production with backup from Puma
*** SIGUSR2 not implemented, signal based restart unavailable!
*** SIGUSR1 not implemented, signal based restart unavailable!
*** SIGHUP not implemented, signal based logs reopening unavailable!
Puma starting in single mode...
* Version 3.9.1 (ruby 2.3.1-p112), codename: Private Caller
* Min threads: 0, max threads: 16
* Environment: development
* Listening on tcp://0.0.0.0:4567
Use Ctrl-C to stop

# [ NOTHING ELSE IS LOGGED ]
```

Once `Ctrl-C` is pressed the error is shown

```powershell
...
== Sinatra has ended his set (crowd applauds)
Shutting down.
C:/tools/ruby2.3.1x64/lib/ruby/2.3.0/open-uri.rb:37:in `initialize': No such file or directory @ rb_sysopen - /var/log/vmpooler.log (Errno::ENOENT)
        from C:/tools/ruby2.3.1x64/lib/ruby/2.3.0/open-uri.rb:37:in `open'
        from C:/tools/ruby2.3.1x64/lib/ruby/2.3.0/open-uri.rb:37:in `open'
        from C:/vmpooler/lib/vmpooler/logger.rb:17:in `log'
        from C:/vmpooler/lib/vmpooler/pool_manager.rb:709:in `execute!'
        from vmpooler:26:in `block in <main>'
```

## Default vmpooler URLs

| Endpoint  | URL                                                                  |
|-----------|----------------------------------------------------------------------|
| Dashboard | [http://localhost:4567/dashboard/](http://localhost:4567/dashboard/) |
| API       | [http://localhost:4567/api/v1]([http://localhost:4567/api/v1)        |

## Use the vmpooler API locally

Once a local vmpooler instance is running you can use any tool you need to interact with the API.  The dummy authentication provider will allow a user to connect if the username and password are not the same:

* Authentication is successful for username `Alice` with password `foo`

* Authentication will fail for username `Alice` with password `Alice`

Like normal vmpooler, tokens will be created for the user and can be used for regular vmpooler operations.
