module Vmpooler
  class Janitor
    def initialize(logger, redis, data_ttl)
      # Load logger library
      $logger = logger

      # Connect to Redis
      $redis = redis

      # TTL
      $data_ttl = data_ttl
    end

    def execute!

      loop do
        $redis.keys('vmpooler__vm__*').each do |key|
          data = $redis.hgetall(key)

          if data['destroy']
            lifetime = (Time.now - Time.parse(data['destroy'])) / 60 / 60

            if lifetime > $data_ttl
              $redis.del(key)
            end
          end
        end

        sleep(600)
      end
    end
  end
end
