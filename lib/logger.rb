require 'rubygems' unless defined?(Gem)

class Logger
  def initialize
  end

  def log level, string
    time = Time.new
    stamp = time.strftime('%Y-%m-%d %H:%M:%S')
    puts "[#{stamp}] #{string}"
  end
end

