# frozen_string_literal: true

require 'pathname'

module Vmpooler
  class Dns
    # Load one or more VMPooler DNS plugin gems by name
    #
    # @param names [Array<String>] The list of gem names to load
    def self.load_by_name(names)
      names = Array(names)
      instance = new
      names.map { |name| instance.load_from_gems(name) }.flatten
    end

    # Returns the plugin class for the specified dns config by name
    #
    # @param config [Object] The entire VMPooler config object
    # @param name [Symbol] The name of the dns config key to get the dns class
    # @return [String] The plugin class for the specifid dns config
    def self.get_dns_plugin_class_by_name(config, name)
      dns_configs = config[:dns_configs].keys
      plugin_class = ''

      dns_configs.map do |dns_config_name|
        plugin_class = config[:dns_configs][dns_config_name]['dns_class'] if dns_config_name.to_s == name
      end

      plugin_class
    end

    # Returns the domain for the specified pool
    #
    # @param config [String] - the full config structure
    # @param pool_name [String] - the name of the pool
    # @return [String] - domain name for pool, which is set via reference to the dns_configs block
    def self.get_domain_for_pool(config, pool_name)
      pool = config[:pools].find { |p| p['name'] == pool_name }
      pool_dns_config = pool['dns_plugin']
      dns_configs = config[:dns_configs].keys
      dns_configs.map do |dns_config_name|
        return config[:dns_configs][dns_config_name]['domain'] if dns_config_name.to_s == pool_dns_config
      end
    end

    # Returns the plugin domain for the specified dns config by name
    #
    # @param config [Object] The entire VMPooler config object
    # @param name [Symbol] The name of the dns config key to get the dns domain
    # @return [String] The domain for the specifid dns config
    def self.get_dns_plugin_domain_by_name(config, name)
      dns_configs = config[:dns_configs].keys
      dns_configs.map do |dns_config_name|
        return config[:dns_configs][dns_config_name]['domain'] if dns_config_name.to_s == name
      end
    end

    # Returns a list of DNS plugin classes specified in the vmpooler configuration
    #
    # @param config [Object] The entire VMPooler config object
    # @return nil || [Array<String>] A list of DNS plugin classes
    def self.get_dns_plugin_config_classes(config)
      return nil unless config[:dns_configs]

      dns_configs = config[:dns_configs].keys
      dns_plugins = dns_configs.map do |dns_config_name|
        if config[:dns_configs][dns_config_name] && config[:dns_configs][dns_config_name]['dns_class']
          config[:dns_configs][dns_config_name]['dns_class'].to_s
        else
          dns_config_name.to_s
        end
      end.compact.uniq

      # dynamic-dns is not actually a class, it's just used as a value to denote
      # that dynamic dns is used so no loading or record management is needed
      dns_plugins.delete('dynamic-dns')

      dns_plugins
    end

    # Load a single DNS plugin gem by name
    #
    # @param name [String] The name of the DNS plugin gem to load
    # @return [String] The full require path to the specified gem
    def load_from_gems(name = nil)
      require_path = "vmpooler/dns/#{name.gsub('-', '/')}"
      require require_path
      require_path
    end
  end
end
