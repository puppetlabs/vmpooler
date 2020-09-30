source ENV['GEM_SOURCE'] || 'https://rubygems.org'

gemspec

# Evaluate Gemfile.local if it exists
if File.exists? "#{__FILE__}.local"
  instance_eval(File.read("#{__FILE__}.local"))
end

# Evaluate ~/.gemfile if it exists
if File.exists?(File.join(Dir.home, '.gemfile'))
  instance_eval(File.read(File.join(Dir.home, '.gemfile')))
end
