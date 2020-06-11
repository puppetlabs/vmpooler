# utility class shared between apps
module Vmpooler
  class Parsing
    def self.get_platform_pool_count(requested, &block)
      requested_platforms = requested.split(',')
      requested_platforms.each do |platform|
        platform_alias, pool, count = platform.split(':')
        raise ArgumentError if platform_alias.nil? || pool.nil? || count.nil?
        yield platform_alias, pool, count
      end
    end
  end
end
