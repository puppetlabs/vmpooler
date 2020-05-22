# frozen_string_literal: true

module Vmpooler
  require 'concurrent'
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

  require 'prometheus/middleware/collector'
  require 'prometheus/middleware/exporter'

  %w[api metrics logger pool_manager generic_connection_pool].each do |lib|
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
      parsed_config[:config]['extra_config'] = ENV['EXTRA_CONFIG'] if ENV['EXTRA_CONFIG']
      if parsed_config[:config]['extra_config']
        extra_configs = parsed_config[:config]['extra_config'].split(',')
        extra_configs.each do |config|
          extra_config = YAML.load_file(config)
          parsed_config.merge!(extra_config)
        end
      end
    end

    parsed_config ||= { config: {} }

    # Bail out if someone attempts to start vmpooler with dummy authentication
    # without enbaling debug mode.
    if parsed_config.key? :auth
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
    parsed_config[:config]['task_limit'] = string_to_int(ENV['TASK_LIMIT']) || parsed_config[:config]['task_limit'] || 10
    parsed_config[:config]['ondemand_clone_limit'] = string_to_int(ENV['ONDEMAND_CLONE_LIMIT']) || parsed_config[:config]['ondemand_clone_limit'] || 10
    parsed_config[:config]['max_ondemand_instances_per_request'] = string_to_int(ENV['MAX_ONDEMAND_INSTANCES_PER_REQUEST']) || parsed_config[:config]['max_ondemand_instances_per_request'] || 10
    parsed_config[:config]['migration_limit'] = string_to_int(ENV['MIGRATION_LIMIT']) if ENV['MIGRATION_LIMIT']
    parsed_config[:config]['vm_checktime'] = string_to_int(ENV['VM_CHECKTIME']) || parsed_config[:config]['vm_checktime'] || 1
    parsed_config[:config]['vm_lifetime'] = string_to_int(ENV['VM_LIFETIME']) || parsed_config[:config]['vm_lifetime'] || 24
    parsed_config[:config]['max_lifetime_upper_limit'] = string_to_int(ENV['MAX_LIFETIME_UPPER_LIMIT']) || parsed_config[:config]['max_lifetime_upper_limit']
    parsed_config[:config]['ready_ttl'] = string_to_int(ENV['READY_TTL']) || parsed_config[:config]['ready_ttl'] || 60
    parsed_config[:config]['ondemand_request_ttl'] = string_to_int(ENV['ONDEMAND_REQUEST_TTL']) || parsed_config[:config]['ondemand_request_ttl'] || 5
    parsed_config[:config]['prefix'] = ENV['PREFIX'] || parsed_config[:config]['prefix'] || ''

    parsed_config[:config]['logfile'] = ENV['LOGFILE'] if ENV['LOGFILE']

    parsed_config[:config]['site_name'] = ENV['SITE_NAME'] if ENV['SITE_NAME']
    parsed_config[:config]['domain'] = ENV['DOMAIN'] if ENV['DOMAIN']
    parsed_config[:config]['clone_target'] = ENV['CLONE_TARGET'] if ENV['CLONE_TARGET']
    parsed_config[:config]['timeout'] = string_to_int(ENV['TIMEOUT']) if ENV['TIMEOUT']
    parsed_config[:config]['vm_lifetime_auth'] = string_to_int(ENV['VM_LIFETIME_AUTH']) if ENV['VM_LIFETIME_AUTH']
    parsed_config[:config]['max_tries'] = string_to_int(ENV['MAX_TRIES']) if ENV['MAX_TRIES']
    parsed_config[:config]['retry_factor'] = string_to_int(ENV['RETRY_FACTOR']) if ENV['RETRY_FACTOR']
    parsed_config[:config]['create_folders'] = true?(ENV['CREATE_FOLDERS']) if ENV['CREATE_FOLDERS']
    parsed_config[:config]['create_template_delta_disks'] = ENV['CREATE_TEMPLATE_DELTA_DISKS'] if ENV['CREATE_TEMPLATE_DELTA_DISKS']
    set_linked_clone(parsed_config)
    parsed_config[:config]['experimental_features'] = ENV['EXPERIMENTAL_FEATURES'] if ENV['EXPERIMENTAL_FEATURES']
    parsed_config[:config]['purge_unconfigured_folders'] = ENV['PURGE_UNCONFIGURED_FOLDERS'] if ENV['PURGE_UNCONFIGURED_FOLDERS']
    parsed_config[:config]['usage_stats'] = ENV['USAGE_STATS'] if ENV['USAGE_STATS']

    parsed_config[:redis] = parsed_config[:redis] || {}
    parsed_config[:redis]['server'] = ENV['REDIS_SERVER'] || parsed_config[:redis]['server'] || 'localhost'
    parsed_config[:redis]['port'] = string_to_int(ENV['REDIS_PORT']) if ENV['REDIS_PORT']
    parsed_config[:redis]['password'] = ENV['REDIS_PASSWORD'] if ENV['REDIS_PASSWORD']
    parsed_config[:redis]['data_ttl'] = string_to_int(ENV['REDIS_DATA_TTL']) || parsed_config[:redis]['data_ttl'] || 168
    parsed_config[:redis]['connection_pool_size'] = string_to_int(ENV['REDIS_CONNECTION_POOL_SIZE']) || parsed_config[:redis]['connection_pool_size'] || 10
    parsed_config[:redis]['connection_pool_timeout'] = string_to_int(ENV['REDIS_CONNECTION_POOL_TIMEOUT']) || parsed_config[:redis]['connection_pool_timeout'] || 5

    parsed_config[:statsd] = parsed_config[:statsd] || {} if ENV['STATSD_SERVER']
    parsed_config[:statsd]['server'] = ENV['STATSD_SERVER'] if ENV['STATSD_SERVER']
    parsed_config[:statsd]['prefix'] = ENV['STATSD_PREFIX'] if ENV['STATSD_PREFIX']
    parsed_config[:statsd]['port'] = string_to_int(ENV['STATSD_PORT']) if ENV['STATSD_PORT']

    parsed_config[:graphite] = parsed_config[:graphite] || {} if ENV['GRAPHITE_SERVER']
    parsed_config[:graphite]['server'] = ENV['GRAPHITE_SERVER'] if ENV['GRAPHITE_SERVER']
    parsed_config[:graphite]['prefix'] = ENV['GRAPHITE_PREFIX'] if ENV['GRAPHITE_PREFIX']
    parsed_config[:graphite]['port'] = string_to_int(ENV['GRAPHITE_PORT']) if ENV['GRAPHITE_PORT']

    parsed_config[:auth] = parsed_config[:auth] || {} if ENV['AUTH_PROVIDER']
    if parsed_config.key? :auth
      parsed_config[:auth]['provider'] = ENV['AUTH_PROVIDER'] if ENV['AUTH_PROVIDER']
      parsed_config[:auth][:ldap] = parsed_config[:auth][:ldap] || {} if parsed_config[:auth]['provider'] == 'ldap'
      parsed_config[:auth][:ldap]['host'] = ENV['LDAP_HOST'] if ENV['LDAP_HOST']
      parsed_config[:auth][:ldap]['port'] = string_to_int(ENV['LDAP_PORT']) if ENV['LDAP_PORT']
      parsed_config[:auth][:ldap]['base'] = ENV['LDAP_BASE'] if ENV['LDAP_BASE']
      parsed_config[:auth][:ldap]['user_object'] = ENV['LDAP_USER_OBJECT'] if ENV['LDAP_USER_OBJECT']
    end

    # Create an index of pool aliases
    parsed_config[:pool_names] = Set.new
    unless parsed_config[:pools]
      redis = new_redis(parsed_config[:redis]['server'], parsed_config[:redis]['port'], parsed_config[:redis]['password'])
      parsed_config[:pools] = load_pools_from_redis(redis)
    end

    # Create an index of pools by title
    parsed_config[:pool_index] = pool_index(parsed_config[:pools])

    parsed_config[:pools].each do |pool|
      parsed_config[:pool_names] << pool['name']
      pool['ready_ttl'] ||= parsed_config[:config]['ready_ttl']
      if pool['alias']
        if pool['alias'].is_a?(Array)
          pool['alias'].each do |pool_alias|
            parsed_config[:alias] ||= {}
            parsed_config[:alias][pool_alias] = [pool['name']] unless parsed_config[:alias].key? pool_alias
            parsed_config[:alias][pool_alias] << pool['name'] unless parsed_config[:alias][pool_alias].include? pool['name']
            parsed_config[:pool_names] << pool_alias
          end
        elsif pool['alias'].is_a?(String)
          parsed_config[:alias][pool['alias']] = pool['name']
          parsed_config[:pool_names] << pool['alias']
        end
      end
    end

    parsed_config[:tagfilter]&.keys&.each do |tag|
      parsed_config[:tagfilter][tag] = Regexp.new(parsed_config[:tagfilter][tag])
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

  def self.redis_connection_pool(host, port, password, size, timeout, metrics)
    Vmpooler::PoolManager::GenericConnectionPool.new(
      metrics: metrics,
      connpool_type: 'redis_connection_pool',
      connpool_provider: 'manager',
      size: size,
      timeout: timeout
    ) do
      connection = Concurrent::Hash.new
      redis = new_redis(host, port, password)
      connection['connection'] = redis
    end
  end

  def self.new_redis(host = 'localhost', port = nil, password = nil)
    Redis.new(host: host, port: port, password: password)
  end

  def self.pools(conf)
    conf[:pools]
  end

  def self.pool_index(pools)
    pools_hash = {}
    index = 0
    pools.each do |pool|
      pools_hash[pool['name']] = index
      index += 1
    end
    pools_hash
  end

  def self.string_to_int(s)
    # Returns a integer if input is a string
    return if s.nil?
    return unless s =~ /\d/

    Integer(s)
  end

  def self.true?(obj)
    obj.to_s.downcase == 'true'
  end

  def self.set_linked_clone(parsed_config) # rubocop:disable Naming/AccessorMethodName
    parsed_config[:config]['create_linked_clones'] = parsed_config[:config]['create_linked_clones'] || true
    parsed_config[:config]['create_linked_clones'] = ENV['CREATE_LINKED_CLONES'] if ENV['CREATE_LINKED_CLONES'] =~ /true|false/
    parsed_config[:config]['create_linked_clones'] = true?(parsed_config[:config]['create_linked_clones']) if parsed_config[:config]['create_linked_clones']
  end
end
