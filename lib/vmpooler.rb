require 'rubygems' unless defined?(Gem)

module Vmpooler
  require 'date'
  require 'json'
  require 'open-uri'
  require 'rbvmomi'
  require 'redis'
  require 'sinatra/base'
  require 'time'
  require 'timeout'
  require 'yaml'
  require 'set'

  %w[api graphite logger pool_manager statsd dummy_statsd generic_connection_pool providers].each do |lib|
    begin
      require "vmpooler/#{lib}"
    rescue LoadError
      require File.expand_path(File.join(File.dirname(__FILE__), 'vmpooler', lib))
    end
  end

  def self.config(filepath = 'vmpooler.yaml')
    parsed_config = {}

    if ENV['VMPOOLER_CONFIG']
      # Load configuration from ENV
      parsed_config = YAML.safe_load(ENV['VMPOOLER_CONFIG'])
    else
      # Load the configuration file from disk
      config_file = File.expand_path(filepath)
      parsed_config = YAML.load_file(config_file)
    end

    # Bail out if someone attempts to start vmpooler with dummy authentication
    # without enbaling debug mode.
    if parsed_config[:auth]['provider'] == 'dummy'
      unless ENV['VMPOOLER_DEBUG']
        warning = [
          'Dummy authentication should not be used outside of debug mode',
          'please set environment variable VMPOOLER_DEBUG to \'true\' if you want to use dummy authentication'
        ]

        raise warning.join(";\s")
      end
    end

    # Set some configuration defaults
    parsed_config[:redis]             ||= {}
    parsed_config[:redis]['server']   ||= 'localhost'
    parsed_config[:redis]['data_ttl'] ||= 168

    parsed_config[:config]['task_limit']   ||= 10
    parsed_config[:config]['vm_checktime'] ||= 15
    parsed_config[:config]['vm_lifetime']  ||= 24
    parsed_config[:config]['prefix']       ||= ''

    # Create an index of pool aliases
    parsed_config[:pool_names] = Set.new
    parsed_config[:pools].each do |pool|
      parsed_config[:pool_names] << pool['name']
      if pool['alias']
        if pool['alias'].is_a?(Array)
          pool['alias'].each do |a|
            parsed_config[:alias] ||= {}
            parsed_config[:alias][a] = pool['name']
            parsed_config[:pool_names] << a
          end
        elsif pool['alias'].is_a?(String)
          parsed_config[:alias][pool['alias']] = pool['name']
          parsed_config[:pool_names] << pool['alias']
        end
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

  def self.new_redis(host = 'localhost')
    Redis.new(host: host)
  end

  def self.new_logger(logfile)
    Vmpooler::Logger.new logfile
  end

  def self.new_metrics(params)
    if params[:statsd]
      Vmpooler::Statsd.new(params[:statsd])
    elsif params[:graphite]
      Vmpooler::Graphite.new(params[:graphite])
    else
      Vmpooler::DummyStatsd.new
    end
  end

  def self.pools(conf)
    conf[:pools]
  end
end
