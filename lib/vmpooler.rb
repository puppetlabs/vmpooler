require 'rubygems' unless defined?(Gem)

module Vmpooler
  require 'date'
  require 'json'
  require 'open-uri'
  require 'rbvmomi'
  require 'redis'
  require 'sinatra/base'
  require "statsd-ruby"
  require 'time'
  require 'timeout'
  require 'yaml'

  %w( api graphite logger pool_manager vsphere_helper ).each do |lib|
    begin
      require "vmpooler/#{lib}"
    rescue LoadError
      require File.expand_path(File.join(File.dirname(__FILE__), 'vmpooler', lib))
    end
  end

  def self.config(filepath='vmpooler.yaml')
    # Load the configuration file
    config_file = File.expand_path(filepath)
    parsed_config = YAML.load_file(config_file)

    # Set some defaults
    parsed_config[:redis]             ||= {}
    parsed_config[:redis]['server']   ||= 'localhost'
    parsed_config[:redis]['data_ttl'] ||= 168

    parsed_config[:config]['task_limit']   ||= 10
    parsed_config[:config]['vm_checktime'] ||= 15
    parsed_config[:config]['vm_lifetime']  ||= 24
    parsed_config[:config]['prefix']       ||= ''

    # Create an index of pool aliases
    parsed_config[:pools].each do |pool|
      if pool['alias']
        if pool['alias'].kind_of?(Array)
          pool['alias'].each do |a|
            parsed_config[:alias] ||= {}
            parsed_config[:alias][a] = pool['name']
          end
        elsif pool['alias'].kind_of?(String)
          parsed_config[:alias][pool['alias']] = pool['name']
        end
      end
    end

    if parsed_config[:graphite]['server']
      parsed_config[:graphite]['prefix'] ||= 'vmpooler'
    end

    # statsd is an addition and my not be present in YAML configuration
    if parsed_config[:statsd]
      if parsed_config[:statsd]['server']
        parsed_config[:statsd]['prefix'] ||= 'vmpooler'
      end
    end

    if parsed_config[:tagfilter]
      parsed_config[:tagfilter].keys.each do |tag|
        parsed_config[:tagfilter][tag] = Regexp.new(parsed_config[:tagfilter][tag])
      end
    end

    parsed_config[:uptime] = Time.now

    parsed_config
  end

  def self.new_redis(host='localhost')
    Redis.new(host: host)
  end

  def self.new_logger(logfile)
    Vmpooler::Logger.new logfile
  end

  def self.new_graphite(server)
    if server.nil? or server.empty? or server.length == 0
      nil
    else
      Vmpooler::Graphite.new server
    end
  end

  def self.new_statsd(server, port)
    if server.nil? or server.empty? or server.length == 0
      nil
    else
      Statsd.new server, port
    end
  end

  def self.pools(conf)
    conf[:pools]
  end
end
