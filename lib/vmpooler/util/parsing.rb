# frozen_string_literal: true

# utility class shared between apps api and pool_manager
module Vmpooler
  class Parsing
    def self.get_platform_pool_count(requested, &_block)
      requested_platforms = requested.split(',')
      requested_platforms.each do |platform|
        platform_alias, pool, count = platform.split(':')
        raise ArgumentError if platform_alias.nil? || pool.nil? || count.nil?

        yield platform_alias, pool, count
      end
    end

    # @param config [String] - the full config structure
    # @param pool_name [String] - the name of the pool
    # @return [String] - domain name for pool, if set in the provider for the pool or in the config block
    def self.get_domain_for_pool(config, pool_name)
      pool = config[:pools].find { |p| p['name'] == pool_name }
      return nil unless pool

      provider_name = pool.fetch('provider', 'vsphere') # see vmpooler.yaml.example where it states defaulting to vsphere

      if config[:providers] && config[:providers][provider_name.to_sym] && config[:providers][provider_name.to_sym]['domain']
        domain = config[:providers][provider_name.to_sym]['domain']
      elsif config[:config] && config[:config]['domain']
        domain = config[:config]['domain']
      else
        domain = nil
      end

      domain
    end
  end
end
