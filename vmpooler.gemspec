lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vmpooler/version'

Gem::Specification.new do |spec|
  spec.name          = 'vmpooler'
  spec.version       = Vmpooler::VERSION
  spec.authors       = ['Puppet']
  spec.email         = ['support@puppet.com']

  spec.summary       = 'vmpooler provides configurable pools of instantly-available (running) virtual machines'
  spec.description   = 'vmpooler provides configurable pools of instantly-available (running) virtual machines'
  spec.homepage      = 'https://github.com/puppetlabs/vmpooler'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_dependency 'puma', '>= 3.6.0'
  spec.add_dependency 'rack', '~> 1.6'
  spec.add_dependency 'rake', '>= 10.4'
  spec.add_dependency 'rbvmomi', '>= 1.8'
  spec.add_dependency 'sinatra', '>= 1.4'
  spec.add_dependency 'net-ldap', '>= 0.16.1'
  spec.add_dependency 'statsd-ruby', '>= 1.3.0'
  spec.add_dependency 'connection_pool', '>= 2.2.1'
  spec.add_dependency 'nokogiri', '>= 1.8.2'
  # we should lock ruby support down to 2.2.2+ and update redis version 3.2
  spec.add_dependency 'redis', '>= 3.0'

end
