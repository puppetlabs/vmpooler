# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'
require 'mock_redis'

describe Vmpooler do
  let(:pools) { [{ 'name' => 'pool1', 'size' => 1 }] }

  # Load the configuration from a YAML string in VMPOOLER_CONFIG, with the given extra
  # settings and environment. Everything else in the environment is left unset.
  def load_config(settings = {}, env = {})
    base = { config: {}, pools: pools }
    unset = %w[VMPOOLER_CONFIG_FILE EXTRA_CONFIG VMPOOLER_DEBUG TASK_LIMIT].to_h { |name| [name, nil] }
    ClimateControl.modify(unset.merge('VMPOOLER_CONFIG' => base.merge(settings).to_yaml, 'VMPOOLER_DEBUG' => 'true').merge(env)) do
      Vmpooler.config
    end
  end

  describe '.config' do
    describe 'defaults' do
      it 'fills in the usual limits and timings' do
        config = load_config[:config]

        expect(config).to include('task_limit' => 10, 'vm_checktime' => 1, 'vm_lifetime' => 24,
                                  'ready_ttl' => 60, 'prefix' => '')
      end

      it 'keeps a value from the config over the default' do
        expect(load_config(config: { 'task_limit' => 3 })[:config]['task_limit']).to eq(3)
      end

      it 'lets the environment win over the config' do
        config = load_config({ config: { 'task_limit' => 3 } }, 'TASK_LIMIT' => '7')

        expect(config[:config]['task_limit']).to eq(7)
      end

      it 'ignores a number that is not a number' do
        expect(load_config({}, 'TASK_LIMIT' => 'bad_data')[:config]['task_limit']).to eq(10)
      end

      it 'notes when it started' do
        expect(load_config[:uptime]).to be_a(Time)
      end
    end

    describe 'settings from the environment' do
      {
        'MIGRATION_LIMIT' => ['migration_limit', 5],
        'VM_CHECKTIME' => ['vm_checktime', 5],
        'VM_LIFETIME' => ['vm_lifetime', 5],
        'MAX_LIFETIME_UPPER_LIMIT' => ['max_lifetime_upper_limit', 5],
        'READY_TTL' => ['ready_ttl', 5],
        'ONDEMAND_REQUEST_TTL' => ['ondemand_request_ttl', 5],
        'ONDEMAND_CLONE_LIMIT' => ['ondemand_clone_limit', 5],
        'MAX_ONDEMAND_INSTANCES_PER_REQUEST' => ['max_ondemand_instances_per_request', 5],
        'TIMEOUT' => ['timeout', 5],
        'TIMEOUT_NOTIFICATION' => ['timeout_notification', 5],
        'VM_LIFETIME_AUTH' => ['vm_lifetime_auth', 5],
        'MAX_TRIES' => ['max_tries', 5],
        'RETRY_FACTOR' => ['retry_factor', 5],
        'PREFIX' => ['prefix', 'test_string'],
        'LOGFILE' => ['logfile', 'test_string'],
        'SITE_NAME' => ['site_name', 'test_string'],
        'CLONE_TARGET' => ['clone_target', 'test_string'],
        'EXPERIMENTAL_FEATURES' => ['experimental_features', 'true'],
        'USAGE_STATS' => ['usage_stats', 'true'],
        'REQUEST_LOGGER' => ['request_logger', 'true'],
        'CREATE_TEMPLATE_DELTA_DISKS' => ['create_template_delta_disks', 'true'],
        'PURGE_UNCONFIGURED_RESOURCES' => ['purge_unconfigured_resources', 'true']
      }.each do |variable, (key, expected)|
        it "sets #{key} from #{variable}" do
          value = expected.is_a?(Integer) ? expected.to_s : expected

          expect(load_config({}, variable => value)[:config][key]).to eq(expected)
        end
      end

      it 'reads CREATE_FOLDERS as a boolean' do
        expect(load_config({}, 'CREATE_FOLDERS' => 'true')[:config]['create_folders']).to be true
        expect(load_config({}, 'CREATE_FOLDERS' => 'no')[:config]['create_folders']).to be false
      end

      it 'creates linked clones unless told not to' do
        expect(load_config[:config]['create_linked_clones']).to be true
        expect(load_config({}, 'CREATE_LINKED_CLONES' => 'false')[:config]['create_linked_clones']).to be false
        expect(load_config({}, 'CREATE_LINKED_CLONES' => 'true')[:config]['create_linked_clones']).to be true
      end

      it 'still accepts the deprecated PURGE_UNCONFIGURED_FOLDERS, and says so' do
        config = nil

        expect { config = load_config({}, 'PURGE_UNCONFIGURED_FOLDERS' => 'true') }
          .to output(/rename ENV var 'PURGE_UNCONFIGURED_FOLDERS' to 'PURGE_UNCONFIGURED_RESOURCES'/).to_stdout
        expect(config[:config]['purge_unconfigured_resources']).to eq('true')
      end

      it 'refuses the removed domain setting in the config' do
        expect { expect { load_config(config: { 'domain' => 'example.com' }) }.to output(/"domain" config setting has been removed/).to_stdout }
          .to raise_error(SystemExit)
      end

      it 'refuses the removed DOMAIN environment variable' do
        expect { expect { load_config({}, 'DOMAIN' => 'example.com') }.to output(/has been removed/).to_stdout }
          .to raise_error(SystemExit)
      end
    end

    describe 'redis' do
      it 'defaults to localhost, a 168 hour data lifetime and no port or password' do
        redis = load_config[:redis]

        expect(redis).to include('server' => 'localhost', 'data_ttl' => 168)
        expect(redis['port']).to be_nil
        expect(redis['password']).to be_nil
      end

      it 'takes its settings from the environment' do
        env = { 'REDIS_SERVER' => 'redis.example', 'REDIS_PORT' => '6380', 'REDIS_PASSWORD' => 'secret',
                'REDIS_DATA_TTL' => '500', 'REDIS_CONNECTION_POOL_SIZE' => '7',
                'REDIS_CONNECTION_POOL_TIMEOUT' => '9', 'REDIS_RECONNECT_ATTEMPTS' => '[0, 1, 5]' }

        expect(load_config({}, env)[:redis]).to include(
          'server' => 'redis.example', 'port' => 6380, 'password' => 'secret', 'data_ttl' => 500,
          'connection_pool_size' => 7, 'connection_pool_timeout' => 9, 'reconnect_attempts' => [0, 1, 5]
        )
      end
    end

    describe 'metrics servers' do
      it 'adds statsd only when a server is given' do
        expect(load_config).not_to have_key(:statsd)

        env = { 'STATSD_SERVER' => 'statsd.example', 'STATSD_PREFIX' => 'mypool', 'STATSD_PORT' => '9125' }
        expect(load_config({}, env)[:statsd]).to eq('server' => 'statsd.example', 'prefix' => 'mypool', 'port' => 9125)
      end

      it 'adds graphite only when a server is given' do
        expect(load_config).not_to have_key(:graphite)

        env = { 'GRAPHITE_SERVER' => 'graphite.example', 'GRAPHITE_PREFIX' => 'mypool', 'GRAPHITE_PORT' => '2004' }
        expect(load_config({}, env)[:graphite]).to eq('server' => 'graphite.example', 'prefix' => 'mypool', 'port' => 2004)
      end
    end

    describe 'tracing' do
      it 'is off by default, with a local jaeger host' do
        expect(load_config[:tracing]).to eq('enabled' => 'false', 'jaeger_host' => 'http://localhost:14268/api/traces')
      end

      it 'takes its settings from the environment' do
        env = { 'VMPOOLER_TRACING_ENABLED' => 'true', 'VMPOOLER_TRACING_JAEGER_HOST' => 'http://jaeger.example/api' }

        expect(load_config({}, env)[:tracing]).to eq('enabled' => 'true', 'jaeger_host' => 'http://jaeger.example/api')
      end
    end

    describe 'authentication' do
      it 'refuses dummy authentication outside debug mode' do
        expect { load_config({ auth: { 'provider' => 'dummy' } }, 'VMPOOLER_DEBUG' => nil) }
          .to raise_error(/Dummy authentication should not be used outside of debug mode/)
      end

      it 'allows dummy authentication in debug mode' do
        expect(load_config(auth: { 'provider' => 'dummy' })[:auth]['provider']).to eq('dummy')
      end

      it 'has no auth settings unless something asks for them' do
        expect(load_config).not_to have_key(:auth)
      end

      it 'builds the ldap settings from the environment' do
        env = { 'AUTH_PROVIDER' => 'ldap', 'LDAP_HOST' => 'ldap.example', 'LDAP_PORT' => '636',
                'LDAP_BASE' => 'dc=example,dc=com', 'LDAP_USER_OBJECT' => 'uid' }

        auth = load_config({}, env)[:auth]

        expect(auth['provider']).to eq('ldap')
        expect(auth[:ldap]).to eq('host' => 'ldap.example', 'port' => 636, 'base' => 'dc=example,dc=com',
                                  'user_object' => 'uid', 'encryption' => {})
      end

      it 'keeps the encryption settings it was given' do
        settings = { auth: { 'provider' => 'ldap', ldap: { 'encryption' => { method: :simple_tls } } } }

        expect(load_config(settings)[:auth][:ldap]['encryption']).to eq(method: :simple_tls)
      end
    end

    describe 'pools' do
      it 'gives each pool the ready TTL unless it has its own' do
        settings = { pools: [{ 'name' => 'a' }, { 'name' => 'b', 'ready_ttl' => 5 }] }

        ttls = load_config(settings)[:pools].map { |pool| pool['ready_ttl'] }

        expect(ttls).to eq([60, 5])
      end

      it 'indexes the pools by name' do
        settings = { pools: [{ 'name' => 'a' }, { 'name' => 'b' }] }

        expect(load_config(settings)[:pool_index]).to eq('a' => 0, 'b' => 1)
      end

      it 'keeps a separate copy of the pools as they were at startup' do
        config = load_config

        config[:pools][0]['size'] = 99

        expect(config[:pools_at_startup][0]['size']).to eq(1)
      end

      it 'lists the pool names and aliases together' do
        settings = { pools: [{ 'name' => 'a', 'alias' => %w[x y] }, { 'name' => 'b' }] }

        expect(load_config(settings)[:pool_names].to_a).to contain_exactly('a', 'b', 'x', 'y')
      end

      it 'maps an alias to every pool that uses it' do
        settings = { pools: [{ 'name' => 'a', 'alias' => ['shared'] }, { 'name' => 'b', 'alias' => %w[shared own] }] }

        expect(load_config(settings)[:alias]).to eq('shared' => %w[a b], 'own' => ['b'])
      end

      it 'accepts an alias written as a single string once the alias map exists' do
        settings = { pools: [{ 'name' => 'a', 'alias' => ['first'] }, { 'name' => 'b', 'alias' => 'second' }] }

        config = load_config(settings)

        expect(config[:alias]['second']).to eq('b')
        expect(config[:pool_names]).to include('second')
      end

      it 'turns the tag filters into regular expressions' do
        config = load_config(tagfilter: { 'url' => '(.*)/' })

        expect(config[:tagfilter]['url']).to eq(%r{(.*)/})
      end

      it 'loads the pools from redis when the config has none' do
        redis = MockRedis.new
        redis.sadd('vmpooler__pools', 'pool9')
        redis.hset('vmpooler__pool__pool9', 'name', 'pool9')
        redis.hset('vmpooler__pool__pool9', 'alias', 'nine,ninety')
        allow(Vmpooler).to receive(:new_redis).and_return(redis)

        config = nil
        expect { config = load_config(pools: nil) }.to output(/loading pools configuration from redis/).to_stdout

        expect(config[:pools]).to eq([{ 'name' => 'pool9', 'alias' => %w[nine ninety], 'ready_ttl' => 60 }])
        expect(config[:pool_names].to_a).to contain_exactly('pool9', 'nine', 'ninety')
      end
    end

    describe 'config from files' do
      let(:file) { File.join(fixtures_dir, 'vmpooler2.yaml') }

      it 'reads the file named in VMPOOLER_CONFIG_FILE' do
        config = ClimateControl.modify(VMPOOLER_CONFIG: nil, VMPOOLER_CONFIG_FILE: file, VMPOOLER_DEBUG: 'true') { Vmpooler.config }

        expect(config[:pools]).to eq(YAML.load_file(file)[:pools])
      end
    end
  end

  describe 'small helpers' do
    it 'turns a string into an integer, or nothing' do
      expect(described_class.string_to_int('12')).to eq(12)
      expect(described_class.string_to_int(nil)).to be_nil
      expect(described_class.string_to_int('bad_data')).to be_nil
    end

    it 'turns an array written as a string into an array, or nothing' do
      expect(described_class.string_array_to_array('[1, 2]')).to eq([1, 2])
      expect(described_class.string_array_to_array(nil)).to be_nil
    end

    it 'reads booleans' do
      expect(described_class.true?('true')).to be true
      expect(described_class.true?('TRUE')).to be true
      expect(described_class.true?(true)).to be true
      expect(described_class.true?('false')).to be false
      expect(described_class.true?(nil)).to be false
    end

    it 'gives the pools of a config' do
      expect(described_class.pools(pools: [{ 'name' => 'a' }])).to eq([{ 'name' => 'a' }])
    end

    it 'indexes pools by name' do
      expect(described_class.pool_index([{ 'name' => 'a' }, { 'name' => 'b' }])).to eq('a' => 0, 'b' => 1)
    end
  end

  describe '.new_redis' do
    it 'connects with the host, port, password and reconnect attempts it is given' do
      expect(Redis).to receive(:new).with(host: 'redis.example', port: 6380, password: 'secret',
                                          reconnect_attempts: 3, connect_timeout: 300).and_return(:redis)

      expect(described_class.new_redis('redis.example', 6380, 'secret', 3)).to eq(:redis)
    end

    it 'defaults to localhost and 10 reconnect attempts' do
      expect(Redis).to receive(:new).with(hash_including(host: 'localhost', reconnect_attempts: 10)).and_return(:redis)

      described_class.new_redis
    end
  end

  describe '.redis_connection_pool' do
    it 'builds a pool of redis connections' do
      redis = MockRedis.new
      expect(described_class).to receive(:new_redis).with('redis.example', 6379, 'secret', 2).and_return(redis)

      pool = described_class.redis_connection_pool('redis.example', 6379, 'secret', 2, 1, nil, 2)

      expect(pool).to be_a(Vmpooler::PoolManager::GenericConnectionPool)
      pool.with_metrics { |connection| expect(connection).to be(redis) }
    end
  end

  describe '.configure_tracing' do
    let(:configurator) { double('configurator', use: nil, add_span_processor: nil, :service_name= => nil, :service_version= => nil, :resource= => nil) }
    let(:processor) { double('span processor') }

    before do
      allow(OpenTelemetry::SDK).to receive(:configure).and_yield(configurator)
      allow(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to receive(:new).and_return(processor)
      allow(OpenTelemetry::Exporter::Jaeger::CollectorExporter).to receive(:new).and_return(:exporter)
      allow(OpenTelemetry::Resource::Detectors::AutoDetector).to receive(:detect).and_return(:resource)
    end

    def configure(args, prefix = '', enabled = 'true')
      described_class.configure_tracing(args, prefix, enabled, 'http://jaeger.example/api', '1.2.3')
    end

    it 'exports spans to jaeger when tracing is on' do
      expect(OpenTelemetry::Exporter::Jaeger::CollectorExporter).to receive(:new).with(endpoint: 'http://jaeger.example/api')

      expect { configure(['api']) }.to output(%r{over HTTP in binary Thrift format to http://jaeger.example/api}).to_stdout
      expect(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to have_received(:new).with(:exporter)
      expect(configurator).to have_received(:add_span_processor).with(processor)
    end

    it 'throws spans away when tracing is off' do
      expect(OpenTelemetry::SDK::Trace::Export::SpanExporter).to receive(:new).and_return(:noop_exporter)

      expect { configure(['api'], '', 'false') }.to output(/Exporting of traces has been disabled/).to_stdout
      expect(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor).to have_received(:new).with(:noop_exporter)
      expect(OpenTelemetry::Exporter::Jaeger::CollectorExporter).not_to have_received(:new)
    end

    it 'names the service after the component and the prefix, and sets the version and resource' do
      configure(['api'], 'prod')

      expect(configurator).to have_received(:service_name=).with('vmpooler-api-prod')
      expect(configurator).to have_received(:service_version=).with('1.2.3')
      expect(configurator).to have_received(:resource=).with(:resource)
    end

    it 'names the manager and a mixed start the same way' do
      configure(['manager'])
      expect(configurator).to have_received(:service_name=).with('vmpooler-manager')

      configure(%w[api manager])
      expect(configurator).to have_received(:service_name=).with('vmpooler')
    end

    it 'turns on the instrumentation for sinatra, concurrent ruby, http client and redis' do
      configure(['api'])

      %w[Sinatra ConcurrentRuby HttpClient Redis].each do |name|
        expect(configurator).to have_received(:use).with("OpenTelemetry::Instrumentation::#{name}")
      end
    end
  end
end
