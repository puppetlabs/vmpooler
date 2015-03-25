module Vmpooler
  class Janitor
    def initialize
      # Load the configuration file
      config_file = File.expand_path('vmpooler.yaml')
      $config = YAML.load_file(config_file)

      # Set some defaults
      $config[:redis]             ||= {}
      $config[:redis]['server']   ||= 'localhost'
      $config[:redis]['data_ttl'] ||= 168

      # Load logger library
      $logger = Vmpooler::Logger.new $config[:config]['logfile']

      # Connect to Redis
      $redis = Redis.new(host: $config[:redis]['server'])
    end

    def execute!

      loop do
        $redis.keys('vmpooler__vm__*').each do |key|
          data = $redis.hgetall(key);

          if data['destroy']
            lifetime = (Time.now - Time.parse(data['destroy'])) / 60 / 60

            if lifetime > $config[:redis]['data_ttl']
              $redis.del(key)
            end
          end
        end

        sleep(600)
      end
    end
  end
end
