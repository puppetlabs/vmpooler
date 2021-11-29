require 'spec_helper'
require 'vmpooler/providers'

describe 'providers' do

  let(:providers) do
    Vmpooler::Providers.new
  end

  it '#correct class' do
    expect(providers).to be_a Vmpooler::Providers
  end

  it '#load_all_providers' do
    expect(Vmpooler::Providers.load_all_providers.join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/base.rb})
    expect(Vmpooler::Providers.load_all_providers.join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/dummy.rb})
  end

  it '#installed_providers' do
    expect(Vmpooler::Providers.installed_providers).to eq(['vmpooler'])
  end

  it '#vmpooler_provider_gem_list' do
    expect(providers.vmpooler_provider_gem_list).to be_a Array
    expect(providers.vmpooler_provider_gem_list.first).to be_a Gem::Specification
  end

  it '#load_by_name' do
    expect(Vmpooler::Providers.load_by_name('dummy').join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/dummy.rb})
    expect(Vmpooler::Providers.load_by_name('dummy').join(', ')).to_not match(%r{,})
  end

  it '#load only dummy' do
    expect(providers.load_from_gems('dummy').join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/dummy.rb})
    expect(providers.load_from_gems('dummy').join(', ')).to_not match(%r{,})
  end

  it '#load all providers from gems' do
    expect(providers.load_from_gems.join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/base.rb})
    expect(providers.load_from_gems.join(', ')).to match(%r{#{project_root_dir}/lib/vmpooler/providers/dummy.rb})
  end


end
