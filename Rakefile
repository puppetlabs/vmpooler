require 'rspec/core/rake_task'

desc 'Run rspec tests with coloring.'
RSpec::Core::RakeTask.new(:test) do |t|
  t.rspec_opts = %w[--color]
  t.pattern    = 'spec/'
end

desc 'Run rspec tests and save JUnit output to results.xml.'
RSpec::Core::RakeTask.new(:junit) do |t|
  t.rspec_opts = %w[-r yarjuf -f JUnit -o results.xml]
  t.pattern    = 'spec/'
end
