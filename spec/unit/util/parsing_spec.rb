require 'spec_helper'

describe 'Parser' do
  let(:pool) { 'pool1' }
  subject { Vmpooler::Parsing }
  describe '.get_domain_for_pool' do
    let(:provider_name) { 'mock_provider' }
    context 'No provider is set' do
      let(:config) { YAML.load(<<~EOT
          ---
          :config:
          :providers:
            :mock_provider:
          :pools:
            - name: '#{pool}'
              size: 1
      EOT
      )}

      it 'should return nil' do
        result = subject.get_domain_for_pool(config, pool)
        expect(result).to be_nil
      end
    end
    context 'Provider is vsphere by default' do
      let(:config) { YAML.load(<<~EOT
          ---
          :config:
          :providers:
            :vsphere:
              domain: myown.com
          :pools:
            - name: '#{pool}'
              size: 1
      EOT
      )}

      it 'should return the domain set for vsphere' do
        result = subject.get_domain_for_pool(config, pool)
        expect(result).to eq('myown.com')
      end
    end
    context 'No domain is set' do
      let(:config) { YAML.load(<<~EOT
          ---
          :config:
          :providers:
            :mock_provider:
          :pools:
            - name: '#{pool}'
              size: 1
              provider: #{provider_name}
      EOT
      )}

      it 'should return nil' do
        result = subject.get_domain_for_pool(config, pool)
        expect(result).to be_nil
      end
    end

    context 'Only a global domain is set' do
      let(:config) { YAML.load(<<~EOT
          ---
          :config:
            domain: example.com
          :providers:
            :mock_provider:
          :pools:
            - name: '#{pool}'
              size: 1
              provider: #{provider_name}
      EOT
      )}

      it 'should return the domain set in the config section' do
        result = subject.get_domain_for_pool(config, pool)
        expect(result).to_not be_nil
        expect(result).to eq('example.com')
      end
    end

    context 'A provider specified a domain to use' do
      let(:config) { YAML.load(<<~EOT
          ---
          :config:
          :providers:
            :mock_provider:
              domain: m.example.com
          :pools:
            - name: '#{pool}'
              size: 1
              provider: #{provider_name}
      EOT
      )}

      it 'should return the domain set in the config section' do
        result = subject.get_domain_for_pool(config, pool)
        expect(result).to_not be_nil
        expect(result).to eq('m.example.com')
      end
    end
  end
end
