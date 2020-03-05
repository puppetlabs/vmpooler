require 'vmpooler'
require 'climate_control'
require 'mock_redis'

describe 'Vmpooler' do
  describe 'config' do

    describe 'environment variables' do

      test_integer = '5'
      test_string = 'test_string'
      test_bool = 'true'
      test_cases = [
        ['migration_limit', test_integer, nil],
        ['task_limit', test_integer, 10],
        ['vm_checktime', test_integer, 1],
        ['vm_lifetime', test_integer, 24],
        ['timeout', test_integer, nil],
        ['vm_lifetime_auth', test_integer, nil],
        ['max_tries', test_integer, nil],
        ['retry_factor', test_integer, nil],
        ['prefix', test_string, ""],
        ['logfile', test_string, nil],
        ['site_name', test_string, nil],
        ['domain', test_string, nil],
        ['clone_target', test_string, nil],
        ['create_folders', test_bool, nil],
        ['create_template_delta_disks', test_bool, nil],
        ['create_linked_clones', test_bool, nil],
        ['experimental_features', test_bool, nil],
        ['purge_unconfigured_folders', test_bool, nil],
        ['usage_stats', test_bool, nil],
        ['extra_config', test_string, nil],
      ]

      test_cases.each do |key, value, default|
        it "should set a value for #{key}" do
          with_modified_env "#{key.upcase}": value do
            test_value = value
            test_value = Integer(value) if value =~ /\d/
            config = Vmpooler.config

            expect(config[:config][key]).to eq(test_value)
          end
        end

        it "should set a default value for each #{key}" do
          config = Vmpooler.config

          expect(config[:config][key]).to eq(default)
        end

        if value =~ /\d/
          it "should not set bad_data as a value for #{key}" do
            with_modified_env "#{key.upcase}": 'bad_data' do
              config = Vmpooler.config

              expect(config[:config][key]).to eq(default)
            end
          end
        end
      end
    end

    describe 'redis environment variables' do
      let(:redis) { MockRedis.new }

      test_cases = [
        ['server', 'redis', 'localhost'],
        ['port', '4567', nil],
        ['password', 'testpass', nil],
        ['data_ttl', '500', 168],
      ]

      test_cases.each do |key, value, default|
        it "should set a value for #{key}" do
          allow(Vmpooler).to receive(:new_redis).and_return(redis)
          with_modified_env "REDIS_#{key.upcase}": value do
            test_value = value
            test_value = Integer(value) if value =~ /\d/
            config = Vmpooler.config

            expect(config[:redis][key]).to eq(test_value)
          end
        end

        it "should set a default value for each #{key}" do
          config = Vmpooler.config

          expect(config[:redis][key]).to eq(default)
        end

        if value =~ /\d/
          it "should not set bad_data as a value for #{key}" do
            with_modified_env "#{key.upcase}": 'bad_data' do
              config = Vmpooler.config

              expect(config[:redis][key]).to eq(default)
            end
          end
        end
      end
    end

    describe 'statsd environment variables' do

      test_cases = [
        ['prefix', 'vmpooler', nil],
        ['port', '4567', nil],
      ]

      test_cases.each do |key, value, default|
        it "should set a value for #{key}" do
          with_modified_env STATSD_SERVER: 'test', "STATSD_#{key.upcase}": value do
            test_value = value
            test_value = Integer(value) if value =~ /\d/
            config = Vmpooler.config

            expect(config[:statsd][key]).to eq(test_value) end
        end

        it "should set a default value for each #{key}" do
          with_modified_env STATSD_SERVER: 'test' do
            config = Vmpooler.config

            expect(config[:statsd][key]).to eq(default)
          end
        end

        if value =~ /\d/
          it "should not set bad_data as a value for #{key}" do
            with_modified_env STATSD_SERVER: 'test', "STATSD_#{key.upcase}": 'bad_data' do
              config = Vmpooler.config

              expect(config[:statsd][key]).to eq(default)
            end
          end
        end
      end
    end

    describe 'graphite environment variables' do

      test_cases = [
        ['prefix', 'vmpooler', nil],
        ['port', '4567', nil],
      ]

      test_cases.each do |key, value, default|
        it "should set a value for #{key}" do
          with_modified_env GRAPHITE_SERVER: 'test', "GRAPHITE_#{key.upcase}": value do
            test_value = value
            test_value = Integer(value) if value =~ /\d/
            config = Vmpooler.config

            expect(config[:graphite][key]).to eq(test_value)
          end
        end

        it "should set a default value for each #{key}" do
          with_modified_env GRAPHITE_SERVER: 'test' do
            config = Vmpooler.config

            expect(config[:graphite][key]).to eq(default)
          end
        end

        if value =~ /\d/
          it "should not set bad_data as a value for #{key}" do
            with_modified_env GRAPHITE_SERVER: 'test', "GRAPHITE_#{key.upcase}": 'bad_data' do
              config = Vmpooler.config

              expect(config[:graphite][key]).to eq(default)
            end
          end
        end
      end
    end

    describe 'ldap environment variables' do

      test_cases = [
        ['host', 'test', nil],
        ['port', '4567', nil],
        ['base', 'dc=example,dc=com', nil],
        ['user_object', 'uid', nil],
      ]

      test_cases.each do |key, value, default|
        it "should set a value for #{key}" do
          with_modified_env AUTH_PROVIDER: 'ldap', "LDAP_#{key.upcase}": value do
            test_value = value
            test_value = Integer(value) if value =~ /\d/
            config = Vmpooler.config

            expect(config[:auth][:ldap][key]).to eq(test_value)
          end
        end

        it "should set a default value for each #{key}" do
          with_modified_env AUTH_PROVIDER: 'ldap' do
            config = Vmpooler.config

            expect(config[:auth][:ldap][key]).to eq(default)
          end
        end

        if value =~ /\d/
          it "should not set bad_data as a value for #{key}" do
            with_modified_env AUTH_PROVIDER: 'ldap', "LDAP_#{key.upcase}": 'bad_data' do
              config = Vmpooler.config

              expect(config[:auth][:ldap][key]).to eq(default)
            end
          end
        end
      end
    end
  end

  def with_modified_env(options, &block)
    ClimateControl.modify(options, &block)
  end
end
