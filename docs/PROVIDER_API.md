# Provider API

Providers facilitate VMPooler interacting with some other system that can create virtual machines. A single VMPooler instance can utilize one or more providers and can have multiple instances of the same provider. An example of having multiple instances of the same provider is when you need to interact with multiple vCenters from the same VMPooler instance.

## Known Providers

- `vmpooler-provider-vsphere` provides the ability to use VMware as a source of VMs. Its code can be found in the [puppetlabs/vmpooler-provider-vsphere](https://github.com/puppetlabs/vmpooler-provider-vsphere) repository.

Know of others? Please submit a pull request to update this list or reach out to us on the Puppet community Slack.

Want to create a new one? See below!

## Create a new provider gem from scratch

### Requirements

1. the provider code will need to be in lib/vmpooler/providers directory of your gem regardless of your gem name
2. the main provider code file should be named the same at the name of the provider. For example, the `vpshere` provider's main file is `lib/vmpooler/providers/vsphere.rb`.
3. The gem must be installed on the same machine as VMPooler
4. The provider name must be referenced in the VMPooler config file in order for it to be loaded.
5. Your gem name and repository name should be `vmpooler-provider-<provider name>` so the community can easily search provider plugins.

The resulting directory structure should resemble this:

```bash
lib/
├── vmpooler/
│   └── providers/
│       └── <provider name>.rb
└── vmpooler-provider-<provider name>/
    └── version.rb
```

### 1. Use bundler to create the provider scaffolding

```bash
bundler gem --test=rspec --no-exe --no-ext vmpooler-provider-spoof
cd vmpooler-providers-spoof/
mkdir -p ./lib/vmpooler/providers
touch ./lib/vmpooler/providers/spoof.rb
mkdir ./lib/vmpooler-providers-spoof
touch ./lib/vmpooler-providers-spoof/version.rb
```

There may be some boilerplate files generated, just delete those.

### 2. Create the main provider file

Ensure the main provider file uses the following code.

```ruby
# lib/vmpooler/providers/spoof.rb
require 'yaml'
require 'vmpooler/providers/base'

module Vmpooler
  class PoolManager
    class Provider
      class Spoof < Vmpooler::PoolManager::Provider::Base
        # At this time it is not documented which methods should be implemented
        # have a look at the https://github.com/puppetlabs/vmpooler-provider-vsphere
        #for an example
      end
    end
  end
end
```

### 3. Create the version file

Ensure you have a version file similar this:

```ruby
# frozen_string_literal: true
# lib/vmpooler-provider-vsphere/version.rb 

module VmpoolerProviderSpoof
  VERSION = '1.0.0'
end
```

### 4. Fill out your gemspec

Ensure you fill out your gemspec file to your specifications.  If you need a dependency, please make sure you require it.

`spec.add_dependency "foo", "~> 1.15"`.

At a minimum you may want to add the `vmpooler` gem as a dev dependency so you can use it during testing.

`spec.add_dev_dependency "vmpooler", "~> 2.0"`

Also make sure this dependency can be loaded by JRuby.  If the dependency cannot be used by JRuby don't use it.

### 5. Create some tests

Your provider code should be tested before releasing. Copy and refactor some tests from the `vmpooler` gem under `spec/unit/providers/dummy_spec.rb`.

### 6. Publish

Think your provider gem is good enough for others?  Publish it and tell us on Slack or update this doc with a link to your gem.
