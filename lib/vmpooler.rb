module Vmpooler
  require 'date'
  require 'json'
  require 'net/ldap'
  require 'open-uri'
  require 'pickup'
  require 'rbvmomi'
  require 'redis'
  require 'set'
  require 'sinatra/base'
  require 'time'
  require 'timeout'
  require 'yaml'

  %w[api graphite logger pool_manager statsd dummy_statsd generic_connection_pool].each do |lib|
    require "vmpooler/#{lib}"
  end

  def self.config(filepath = 'vmpooler.yaml')
    # Take the config either from an ENV config variable or from a config file
    if ENV['VMPOOLER_CONFIG']
      config_string = ENV['VMPOOLER_CONFIG']
      # Parse the YAML config into a Hash
      # Whitelist the Symbol class
      parsed_config = YAML.safe_load(config_string, [Symbol])
    else
      # Take the name of the config file either from an ENV variable or from the filepath argument
      config_file = ENV['VMPOOLER_CONFIG_FILE'] || filepath
      parsed_config = YAML.load_file(config_file) if File.exist? config_file
    end

    parsed_config ||= { config: {} }

    # Bail out if someone attempts to start vmpooler with dummy authentication
    # without enbaling debug mode.
    if parsed_config.has_key? :auth
      if parsed_config[:auth]['provider'] == 'dummy'
        unless ENV['VMPOOLER_DEBUG']
          warning = [
            'Dummy authentication should not be used outside of debug mode',
            'please set environment variable VMPOOLER_DEBUG to \'true\' if you want to use dummy authentication'
          ]

          raise warning.join(";\s")
        end
      end
    end

    # Set some configuration defaults
    parsed_config[:config]['task_limit'] = ENV['TASK_LIMIT'] || parsed_config[:config]['task_limit'] || 10
    parsed_config[:config]['migration_limit'] = ENV['MIGRATION_LIMIT'] if ENV['MIGRATION_LIMIT']
    parsed_config[:config]['vm_checktime'] = ENV['VM_CHECKTIME'] || parsed_config[:config]['vm_checktime'] || 15
    parsed_config[:config]['vm_lifetime'] = ENV['VM_LIFETIME'] || parsed_config[:config]['vm_lifetime']  || 24
    parsed_config[:config]['prefix'] = ENV['VM_PREFIX'] || parsed_config[:config]['prefix'] || ''

    parsed_config[:config]['logfile'] = ENV['LOGFILE'] if ENV['LOGFILE']

    parsed_config[:config]['site_name'] = ENV['SITE_NAME'] if ENV['SITE_NAME']
    parsed_config[:config]['domain'] = ENV['DOMAIN_NAME'] if ENV['DOMAIN_NAME']
    parsed_config[:config]['clone_target'] = ENV['CLONE_TARGET'] if ENV['CLONE_TARGET']
    parsed_config[:config]['timeout'] = ENV['TIMEOUT'] if ENV['TIMEOUT']
    parsed_config[:config]['vm_lifetime_auth'] = ENV['VM_LIFETIME_AUTH'] if ENV['VM_LIFETIME_AUTH']
    parsed_config[:config]['max_tries'] = ENV['MAX_TRIES'] if ENV['MAX_TRIES']
    parsed_config[:config]['retry_factor'] = ENV['RETRY_FACTOR'] if ENV['RETRY_FACTOR']
    parsed_config[:config]['create_folders'] = ENV['CREATE_FOLDERS'] if ENV['CREATE_FOLDERS']
    parsed_config[:config]['create_template_delta_disks'] = ENV['CREATE_TEMPLATE_DELTA_DISKS'] if ENV['CREATE_TEMPLATE_DELTA_DISKS']
    parsed_config[:config]['experimental_features'] = ENV['EXPERIMENTAL_FEATURES'] if ENV['EXPERIMENTAL_FEATURES']
    parsed_config[:config]['purge_unconfigured_folders'] = ENV['PURGE_UNCONFIGURED_FOLDERS'] if ENV['PURGE_UNCONFIGURED_FOLDERS']

    parsed_config[:redis] = parsed_config[:redis] || {}
    parsed_config[:redis]['server'] = ENV['REDIS_SERVER'] || parsed_config[:redis]['server'] || 'localhost'
    parsed_config[:redis]['port'] = ENV['REDIS_PORT'] if ENV['REDIS_PORT']
    parsed_config[:redis]['password'] = ENV['REDIS_PASSWORD'] if ENV['REDIS_PASSWORD']
    parsed_config[:redis]['data_ttl'] = ENV['REDIS_DATA_TTL'] || parsed_config[:redis]['data_ttl'] || 168

    parsed_config[:statsd] = parsed_config[:statsd] || {} if ENV['STATSD_SERVER']
    parsed_config[:statsd]['server'] = ENV['STATSD_SERVER'] if ENV['STATSD_SERVER']
    parsed_config[:statsd]['prefix'] = ENV['STATSD_PREFIX'] if ENV['STATSD_PREFIX']
    parsed_config[:statsd]['port'] = ENV['STATSD_PORT'] if ENV['STATSD_PORT']

    parsed_config[:graphite] = parsed_config[:graphite] || {} if ENV['GRAPHITE_SERVER']
    parsed_config[:graphite]['server'] = ENV['GRAPHITE_SERVER'] if ENV['GRAPHITE_SERVER']
    parsed_config[:graphite]['prefix'] = ENV['GRAPHITE_PREFIX'] if ENV['GRAPHITE_PREFIX']
    parsed_config[:graphite]['port'] = ENV['GRAPHITE_PORT'] if ENV['GRAPHITE_PORT']

    parsed_config[:auth] = parsed_config[:auth] || {} if ENV['AUTH_PROVIDER']
    if parsed_config.has_key? :auth
      parsed_config[:auth]['provider'] = ENV['AUTH_PROVIDER'] if ENV['AUTH_PROVIDER']
      parsed_config[:auth][:ldap] = parsed_config[:auth][:ldap] || {} if parsed_config[:auth]['provider'] == 'ldap'
      parsed_config[:auth][:ldap]['host'] = ENV['LDAP_HOST'] if ENV['LDAP_HOST']
      parsed_config[:auth][:ldap]['port'] = ENV['LDAP_PORT'] if ENV['LDAP_PORT']
      parsed_config[:auth][:ldap]['base'] = ENV['LDAP_BASE'] if ENV['LDAP_BASE']
      parsed_config[:auth][:ldap]['user_object'] = ENV['LDAP_USER_OBJECT'] if ENV['LDAP_USER_OBJECT']
    end

    # Create an index of pool aliases
    parsed_config[:pool_names] = Set.new
    unless parsed_config[:pools]
      redis = new_redis(parsed_config[:redis]['server'], parsed_config[:redis]['port'], parsed_config[:redis]['password'])
      parsed_config[:pools] = load_pools_from_redis(redis)
    end

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

  def self.load_pools_from_redis(redis)
    pools = []
    redis.smembers('vmpooler__pools').each do |pool|
      pool_hash = {}
      redis.hgetall("vmpooler__pool__#{pool}").each do |k, v|
        pool_hash[k] = v
      end
      pool_hash['alias'] = pool_hash['alias'].split(',')
      pools << pool_hash
    end
    pools
  end

  def self.new_redis(host = 'localhost', port = nil, password = nil)
    Redis.new(host: host, port: port, password: password)
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
