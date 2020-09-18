source ENV['GEM_SOURCE'] || 'https://rubygems.org'

gem 'json', '>= 1.8'
gem 'pickup', '~> 0.0.11'
gem 'puma', '~> 4.3'
gem 'rack', '~> 2.2'
gem 'rake', '~> 13.0'
gem 'redis', '~> 4.1'
gem 'rbvmomi', '~> 3.0'
gem 'sinatra', '~> 2.0'
gem 'prometheus-client', '~> 2.0'
gem 'net-ldap', '~> 0.16'
gem 'statsd-ruby', '~> 1.4.0', :require => 'statsd'
gem 'connection_pool', '~> 2.2'
gem 'nokogiri', '~> 1.10'
gem 'spicy-proton', '~> 2.1'
gem 'concurrent-ruby', '~> 1.1'

group :development do
  gem 'pry'
end

# Test deps
group :test do
  # required in order for the providers auto detect mechanism to work
  gem 'vmpooler', path: './'
  gem 'mock_redis', '>= 0.17.0'
  gem 'rack-test', '>= 0.6'
  gem 'rspec', '>= 3.2'
  gem 'simplecov', '>= 0.11.2'
  gem 'yarjuf', '>= 2.0'
  gem 'climate_control', '>= 0.2.0'
  # Rubocop would be ok jruby but for now we only use it on
  # MRI or Windows platforms
  gem "rubocop", :platforms => [:ruby, :x64_mingw]
end

# Evaluate Gemfile.local if it exists
if File.exists? "#{__FILE__}.local"
  instance_eval(File.read("#{__FILE__}.local"))
end

# Evaluate ~/.gemfile if it exists
if File.exists?(File.join(Dir.home, '.gemfile'))
  instance_eval(File.read(File.join(Dir.home, '.gemfile')))
end
