require 'rubygems' unless defined?(Gem)

module Vmpooler
  class Graphite
    attr_reader :server, :port, :prefix

    def initialize(params = {})
      if params["server"].nil? || params["server"].empty?
        raise ArgumentError, "Graphite server is required. Config: #{params.inspect}"
      end

      @server = params["server"]
      @port   = params["port"]   || 2003
      @prefix = params["prefix"] || "vmpooler"
    end

    def increment(label)
      log label, 1
    end

    def gauge(label, value)
      log label, value
    end

    def timing(label, duration)
      log label, duration
    end

    def log(path, value)
      Thread.new do
        socket = TCPSocket.new(server, port)
        begin
          socket.puts "#{prefix}.#{path} #{value} #{Time.now.to_i}"
        ensure
          socket.close
        end
      end
    rescue => err
      $stderr.puts "Failure logging #{path} to graphite server [#{server}:#{port}]: #{err}"
    end
  end
end
