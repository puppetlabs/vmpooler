# Provider API

## Create a new provider gem from scratch

### Requirements
1. the provider code will need to be in lib/vmpooler/providers directory of your gem regardless of your gem name
2. the main provider code file should be named the same at the name of the provider. ie. (vpshere == lib/vmpooler/providers/vsphere.rb)
3. The gem must be installed on the same machine as vmpooler
4. The provider name must be referenced in the vmpooler config file in order for it to be loaded.
5. Your gem name or repository name should contain vmpooler-<name>-provider so the community can easily search provider plugins
   for vmpooler.
### 1. Use bundler to create the provider scaffolding

```
bundler gem --test=rspec --no-exe --no-ext vmpooler-spoof-provider
cd vmpooler-providers-spoof/
mkdir -p ./lib/vmpooler/providers
cd ./lib/vmpooler/providers
touch spoof.rb

```

There may be some boilerplate files there were generated, just delete those.

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
      
      # at this time it is not documented which methods should be implemented
      # have a look at the vmpooler/providers/vpshere provider for examples

      end

    end
  end
end
  

```

### 3. Fill out your gemspec
Ensure you fill out your gemspec file to your specifications.  If you need a dependency please make sure you require them.

`spec.add_dependency "vmware", "~> 1.15"`.

At a minimum you may want to add the vmpooler gem as a dev dependency so you can use it during testing.

`spec.add_dev_dependency "vmpooler", "~> 1.15"`

or in your Gemfile

```ruby

gem 'vmpooler', github: 'puppetlabs/vmpooler'
```

Also make sure this dependency can be loaded by jruby.  If the dependency cannot be used by jruby don't use it.

### 4. Create some tests
Your provider code should be tested before releasing.  Copy and refactor some tests from the vmpooler gem under 
`spec/unit/providers/dummy_spec.rb`

### 5. Publish
Think your provider gem is good enough for others?  Publish it and tell us on Slack or update this doc with a link to your gem.


## Available Third Party Providers
Be the first to update this list.  Create a provider today!


## Example provider
You can use the following [repo as an example](https://github.com/logicminds/vmpooler-vsphere-provider) of how to setup your provider gem.

