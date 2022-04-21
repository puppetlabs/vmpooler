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
  s.add_dependency 'concurrent-ruby', '~> 1.1'
  s.add_dependency 'connection_pool', '~> 2.2'
  s.add_dependency 'deep_merge', '~> 1.2'
  s.add_dependency 'net-ldap', '~> 0.16'
  s.add_dependency 'nokogiri', '~> 1.10'
  s.add_dependency 'opentelemetry-exporter-jaeger', '= 0.20.1'
  s.add_dependency 'opentelemetry-instrumentation-concurrent_ruby', '= 0.19.2'
  s.add_dependency 'opentelemetry-instrumentation-http_client', '= 0.19.3'
  s.add_dependency 'opentelemetry-instrumentation-redis', '= 0.21.2'
  s.add_dependency 'opentelemetry-instrumentation-sinatra', '= 0.19.3'
  s.add_dependency 'opentelemetry-resource_detectors', '= 0.19.1'
  s.add_dependency 'opentelemetry-sdk', '~> 1.0', '>= 1.0.2'
  s.add_dependency 'pickup', '~> 0.0.11'
  s.add_dependency 'prometheus-client', '~> 2.0'
  s.add_dependency 'puma', '~> 5.0', '>= 5.0.4'
  s.add_dependency 'rack', '~> 2.2'
  s.add_dependency 'rake', '~> 13.0'
  s.add_dependency 'redis', '~> 4.1'
  s.add_dependency 'sinatra', '~> 2.0'
  s.add_dependency 'spicy-proton', '~> 2.1'
  s.add_dependency 'statsd-ruby', '~> 1.4'

  # Testing dependencies
  s.add_development_dependency 'climate_control', '>= 0.2.0'
  s.add_development_dependency 'mock_redis', '>= 0.17.0'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'rack-test', '>= 0.6'
  s.add_development_dependency 'rspec', '>= 3.2'
  s.add_development_dependency 'rubocop', '~> 1.28.1'
  s.add_development_dependency 'simplecov', '>= 0.11.2'
  s.add_development_dependency 'thor', '~> 1.0', '>= 1.0.1'
  s.add_development_dependency 'yarjuf', '>= 2.0'
end
