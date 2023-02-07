module Vmpooler
  class PoolManager
    class Dns
      class Base
         # These defs must be overidden in child classes

        # Helper Methods
        # Global Logger object
        attr_reader :logger
        # Global Metrics object
        attr_reader :metrics
        # Provider options passed in during initialization
        attr_reader :dns_options

        def initialize(config, logger, metrics, redis_connection_pool, name, options)
          @config = config
          @logger = logger
          @metrics = metrics
          @redis = redis_connection_pool
          @dns_plugin_name = name

          @dns_options = options

          logger.log('s', "[!] Creating dns plugin '#{name}'")
          # Your code goes here...
        end

        def pool_config(pool_name)
          # Get the configuration of a specific pool
          @config[:pools].each do |pool|
            return pool if pool['name'] == pool_name
          end

          nil
        end

        # Returns this dns plugin's configuration
        #
        # @returns [Hashtable] This dns plugins's configuration from the config file.  Returns nil if the dns plugin config does not exist
        def dns_config
          @config[:dns_configs].each do |dns|
            # Convert the symbol from the config into a string for comparison
            return (dns[1].nil? ? {} : dns[1]) if dns[0].to_s == @dns_plugin_name
          end

          nil
        end

        def global_config
          # This entire VM Pooler config
          @config
        end

        def name
          @dns_plugin_name
        end

        def get_ip(vm_name)
          @redis.with_metrics do |redis|
            ip = redis.hget("vmpooler__vm__#{vm_name}", 'ip')
            return ip
          end
        end

        # returns
        #   Array[String] : Array of pool names this provider services
        def provided_pools
          list = []
          @config[:pools].each do |pool|
            list << pool['name'] if pool['dns_config'] == name
          end
          list
        end

        def create_or_replace_record(hostname)
          raise("#{self.class.name} does not implement create_or_replace_record")
        end

        def delete_record(hostname)
          raise("#{self.class.name} does not implement delete_record")
        end
      end
    end
  end
end