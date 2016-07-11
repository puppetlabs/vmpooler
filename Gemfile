source ENV['GEM_SOURCE'] || 'https://rubygems.org'

if RUBY_VERSION =~ /^1\.9\./
  gem 'json', '~> 1.8'
else
  gem 'json', '>= 1.8'
end

gem 'rack', '>= 1.6'
gem 'rake', '>= 10.4'
gem 'rbvmomi', '>= 1.8'
gem 'redis', '>= 3.2'
gem 'sinatra', '>= 1.4'
gem 'net-ldap', '<= 0.12.1' # keep compatibility w/ jruby & mri-1.9.3

# Test deps
group :test do
  gem 'rack-test', '>= 0.6'
  gem 'rspec', '>= 3.2'
  gem 'yarjuf', '>= 2.0'
end
