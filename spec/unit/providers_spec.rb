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
    p = [
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'base.rb'),
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'dummy.rb'),
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'vsphere.rb')
    ]
    expect(Vmpooler::Providers.load_all_providers).to eq(p)
  end

  it '#installed_providers' do
    expect(Vmpooler::Providers.installed_providers).to eq(['vmpooler'])
  end

  it '#vmpooler_provider_gem_list' do
    expect(providers.vmpooler_provider_gem_list).to be_a Array
    expect(providers.vmpooler_provider_gem_list.first).to be_a Gem::Specification
  end

  it '#load_by_name' do
    expect(Vmpooler::Providers.load_by_name('vsphere')).to eq([File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'vsphere.rb')])
  end

  it '#load only vpshere' do
    expect(providers.load_from_gems('vsphere')).to eq([File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'vsphere.rb')])
  end

  it '#load all providers from gems' do
    p = [
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'base.rb'),
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'dummy.rb'),
        File.join(project_root_dir, 'lib', 'vmpooler', 'providers', 'vsphere.rb')
    ]
    expect(providers.load_from_gems).to eq(p)

  end


end
