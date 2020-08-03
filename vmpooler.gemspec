lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vmpooler/version'

Gem::Specification.new do |s|
  s.name          = 'vmpooler'
  s.version       = Vmpooler::VERSION
  s.authors       = ['Puppet']
  s.email         = ['support@puppet.com']

  s.summary       = 'vmpooler provides configurable pools of instantly-available (running) virtual machines'
  s.homepage      = 'https://github.com/puppetlabs/vmpooler'
  s.license       = 'Apache-2.0'
  s.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  s.files         = Dir[ "bin/*", "lib/**/*" ]
  s.bindir        = 'bin'
  s.executables   = 'vmpooler'
  s.require_paths = ["lib"]
  s.add_dependency 'pickup', '~> 0.0.11'
  s.add_dependency 'puma', '~> 4.3'
  s.add_dependency 'rack', '~> 2.2'
  s.add_dependency 'rake', '~> 13.0'
  s.add_dependency 'redis', '~> 4.1'
  s.add_dependency 'rbvmomi', '>= 2.1', '< 4.0'
  s.add_dependency 'sinatra', '~> 2.0'
  s.add_dependency 'prometheus-client', '~> 2.0'
  s.add_dependency 'net-ldap', '~> 0.16'
  s.add_dependency 'statsd-ruby', '~> 1.4'
  s.add_dependency 'connection_pool', '~> 2.2'
  s.add_dependency 'concurrent-ruby', '~> 1.1'
  s.add_dependency 'nokogiri', '~> 1.10'
  s.add_dependency 'spicy-proton', '~> 2.1'
end
