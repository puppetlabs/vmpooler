require 'rubygems' unless defined?(Gem)

class Logger
  def initialize(
    f = '/var/log/vmware-host-pooler.log'
  )
    @file = f
  end

  def log level, string
    time = Time.new
    stamp = time.strftime('%Y-%m-%d %H:%M:%S')
    puts "[#{stamp}] #{string}"

    open(@file, 'a') do |f|
      f.puts "[#{stamp}] #{string}"
    end
  end
end

