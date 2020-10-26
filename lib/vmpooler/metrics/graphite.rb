# frozen_string_literal: true

require 'rubygems' unless defined?(Gem)

module Vmpooler
  class Metrics
    class Graphite < Metrics
      attr_reader :server, :port, :prefix

      # rubocop:disable Lint/MissingSuper
      def initialize(logger, params = {})
        raise ArgumentError, "Graphite server is required. Config: #{params.inspect}" if params['server'].nil? || params['server'].empty?

        @server = params['server']
        @port   = params['port'] || 2003
        @prefix = params['prefix'] || 'vmpooler'
        @logger = logger
      end
      # rubocop:enable Lint/MissingSuper

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
      rescue Errno::EADDRNOTAVAIL => e
        warn "Could not assign address to graphite server #{server}: #{e}"
      rescue StandardError => e
        @logger.log('s', "[!] Failure logging #{path} to graphite server [#{server}:#{port}]: #{e}")
      end
    end
  end
end
