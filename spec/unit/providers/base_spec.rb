require 'spec_helper'

# This spec does not really exercise code paths but is merely used
# to enforce that certain methods are defined in the base classes

describe 'Vmpooler::PoolManager::Provider::Base' do
  let(:config) { {} }
  let(:fake_vm) {
    fake_vm = {}
    fake_vm['name'] = 'vm1'
    fake_vm['hostname'] = 'vm1'
    fake_vm['template'] = 'pool1'
    fake_vm['boottime'] = Time.now
    fake_vm['powerstate'] = 'PoweredOn'

    fake_vm
  }

  subject { Vmpooler::PoolManager::Provider::Base.new(config) }

  describe '#name' do
    it 'should be base' do
      expect(subject.name).to eq('base')
    end
  end

  describe '#vms_in_pool' do
    it 'should raise error' do
      expect{subject.vms_in_pool('pool')}.to raise_error(/does not implement vms_in_pool/)
    end
  end

  describe '#get_vm_host' do
    it 'should raise error' do
      expect{subject.get_vm_host('vm')}.to raise_error(/does not implement get_vm_host/)
    end
  end

  describe '#find_least_used_compatible_host' do
    it 'should raise error' do
      expect{subject.find_least_used_compatible_host('vm')}.to raise_error(/does not implement find_least_used_compatible_host/)
    end
  end

  describe '#migrate_vm_to_host' do
    it 'should raise error' do
      expect{subject.migrate_vm_to_host('vm','host')}.to raise_error(/does not implement migrate_vm_to_host/)
    end
  end

  describe '#get_vm' do
    it 'should raise error' do
      expect{subject.get_vm('vm')}.to raise_error(/does not implement get_vm/)
    end
  end

  describe '#create_vm' do
    it 'should raise error' do
      expect{subject.create_vm('pool','newname')}.to raise_error(/does not implement create_vm/)
    end
  end

  describe '#destroy_vm' do
    it 'should raise error' do
      expect{subject.destroy_vm('vm','pool')}.to raise_error(/does not implement destroy_vm/)
    end
  end

  describe '#vm_ready?' do
    it 'should raise error' do
      expect{subject.vm_ready?('vm','pool','timeout')}.to raise_error(/does not implement vm_ready?/)
    end
  end

  describe '#vm_exists?' do
    it 'should raise error' do
      expect{subject.vm_exists?('vm')}.to raise_error(/does not implement/)
    end

    it 'should return true when get_vm returns an object' do
      allow(subject).to receive(:get_vm).with('vm').and_return(fake_vm)

      expect(subject.vm_exists?('vm')).to eq(true)
    end

    it 'should return false when get_vm returns nil' do
      allow(subject).to receive(:get_vm).with('vm').and_return(nil)

      expect(subject.vm_exists?('vm')).to eq(false)
    end
  end
end
