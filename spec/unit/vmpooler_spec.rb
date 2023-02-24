require 'spec_helper'

describe 'Vmpooler' do
  describe '.config' do
    let(:config_file) { File.join(fixtures_dir, 'vmpooler2.yaml') }
    let(:config) { YAML.load_file(config_file) }

    before(:each) do
      ENV['VMPOOLER_DEBUG'] = 'true'
      ENV['VMPOOLER_CONFIG_FILE'] = nil
      ENV['VMPOOLER_CONFIG'] = nil
    end

    context 'when no config is given' do
      it 'defaults to vmpooler.yaml' do
        default_config_file = File.join(fixtures_dir, 'vmpooler.yaml')
        default_config = YAML.load_file(default_config_file)

        Dir.chdir(fixtures_dir) do
          expect(Vmpooler.config[:pools]).to eq(default_config[:pools])
        end
      end

      it 'keeps a copy of the original pools at startup' do
        Dir.chdir(fixtures_dir) do
          configuration = Vmpooler.config
          expect(configuration[:pools]).to eq(configuration[:pools_at_startup])
        end
      end

      it 'the copy is a separate object and not a reference' do
        Dir.chdir(fixtures_dir) do
          configuration = Vmpooler.config
          configuration[:pools][0]['template'] = 'sam'
          expect(configuration[:pools]).not_to eq(configuration[:pools_at_startup])
        end
      end
    end

    context 'when config variable is set' do
      it 'should use the config' do
        ENV['VMPOOLER_CONFIG'] = config.to_yaml
        expect(Vmpooler.config[:pools]).to eq(config[:pools])
      end
    end

    context 'when config file is set' do
      before(:each) do
        ENV['VMPOOLER_CONFIG_FILE'] = config_file
      end
      it 'should use the file' do
        expect(Vmpooler.config[:pools]).to eq(config[:pools])
      end
      it 'merges one extra file, results in two providers' do
        ENV['EXTRA_CONFIG'] = File.join(fixtures_dir, 'extra_config1.yaml')
        expect(Vmpooler.config[:providers].keys).to include(:dummy)
        expect(Vmpooler.config[:providers].keys).to include(:alice)
      end
      it 'merges two extra file, results in three providers and an extra pool' do
        extra1 = File.join(fixtures_dir, 'extra_config1.yaml')
        extra2 = File.join(fixtures_dir, 'extra_config2.yaml')
        ENV['EXTRA_CONFIG'] = "#{extra1},#{extra2}"
        expect(Vmpooler.config[:providers].keys).to include(:dummy)
        expect(Vmpooler.config[:providers].keys).to include(:alice)
        expect(Vmpooler.config[:providers].keys).to include(:bob)
        merged_pools = [{"name"=>"pool03", "provider"=>"dummy", "dns_plugin"=>"example", "ready_ttl"=>5, "size"=>5},
                        {"name"=>"pool04", "provider"=>"dummy", "dns_plugin"=>"example", "ready_ttl"=>5, "size"=>5},
                        {"name"=>"pool05", "provider"=>"dummy", "dns_plugin"=>"example", "ready_ttl"=>5, "size"=>5}]
        expect(Vmpooler.config[:pools]).to eq(merged_pools)
        expect(Vmpooler.config[:config]).not_to be_nil #merge does not deleted existing keys
      end
    end
  end
end
