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
  s.add_dependency 'puma', '~> 3.11'
  s.add_dependency 'rack', '~> 2.0'
  s.add_dependency 'rake', '~> 12.3'
  s.add_dependency 'redis', '~> 4.0'
  s.add_dependency 'rbvmomi', '~> 1.13'
  s.add_dependency 'sinatra', '~> 2.0'
  s.add_dependency 'net-ldap', '~> 0.16'
  s.add_dependency 'statsd-ruby', '~> 1.4'
  s.add_dependency 'connection_pool', '~> 2.2'
  s.add_dependency 'nokogiri', '~> 1.8'
end
