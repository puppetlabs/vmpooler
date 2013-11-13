require 'rubygems' unless defined?(Gem)

class Graphite
  def initialize(
    s = 'graphite'
  )
    @server = s
  end

  def log path, value
    Thread.new {
      socket = TCPSocket.new(@server, 2003)
      socket.puts "#{path} #{value} #{Time.now.to_i}"
      socket.close
    }
  end
end

