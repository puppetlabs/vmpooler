require 'spec_helper'

describe 'Pool Manager' do
  let(:logger) { double('logger') }
  let(:redis) { double('redis') }
  let(:config) { {} }
  let(:pools) { {} }
  let(:graphite) { nil }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) { double('host') }

  subject { Vmpooler::PoolManager.new(config, pools, logger, redis, graphite) }

  describe '#_check_pending_vm' do
    let(:pool_helper) { double('pool') }
    let(:vsphere) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $vsphere = vsphere
    end

    context 'host not in pool' do

      it 'calls fail_pending_vm' do
        allow(pool_helper).to receive(:find_vm).and_return(nil)
        allow(redis).to receive(:hget)
        expect(redis).to receive(:hget).with(String, 'clone').once
        subject._check_pending_vm(vm, pool, timeout)
      end

    end

    context 'host is in pool' do
      let(:vm_finder) { double('vm_finder') }

      it 'calls move_pending_vm_to_ready' do
        allow(pool_helper).to receive(:find_vm).and_return(vm_finder)
        allow(vm_finder).to receive(:summary).and_return(nil)

        expect(vm_finder).to receive(:summary).once
        expect(redis).not_to receive(:hget).with(String, 'clone')

        subject._check_pending_vm(vm, pool, timeout)
      end
    end
  end

  describe '#move_vm_to_ready' do
    before do
      expect(subject).not_to be_nil
    end

    context 'a host without correct summary' do

      it 'does nothing when summary is nil' do
        allow(host).to receive(:summary).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when guest is nil' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when hostName is nil' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return nil
        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'does nothing when hostName does not match vm' do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return 'adifferentvm'
        subject.move_pending_vm_to_ready(vm, pool, host)
      end
    end

    context 'a host with proper summary' do
      before do
        allow(host).to receive(:summary).and_return true
        allow(host).to receive_message_chain(:summary, :guest).and_return true
        allow(host).to receive_message_chain(:summary, :guest, :hostName).and_return vm

        allow(redis).to receive(:hget)
        allow(redis).to receive(:smove)
        allow(redis).to receive(:hset)
        allow(logger).to receive(:log)
      end

      it 'moves vm to ready' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return Time.now.to_s

        expect(redis).to receive(:smove).with(String, String, vm)
        expect(redis).to receive(:hset).with(String, String, String)
        expect(logger).to receive(:log).with('s', String)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

      it 'sets finish to nil when clone_time is nil' do
        expect(redis).to receive(:smove).with(String, String, vm)
        expect(redis).to receive(:hset).with(String, String, nil)
        expect(logger).to receive(:log).with('s', String)

        subject.move_pending_vm_to_ready(vm, pool, host)
      end

    end
  end

  describe '#fail_pending_vm' do
    before do
      expect(subject).not_to be_nil
    end

    context 'does not have a clone stamp' do
      it 'has no side effects' do
        allow(redis).to receive(:hget)
        subject.fail_pending_vm(vm, pool, timeout)
      end
    end

    context 'has valid clone stamp' do
      it 'does nothing when less than timeout' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return Time.now.to_s
        subject.fail_pending_vm(vm, pool, timeout)
      end

      it 'moves vm to completed when over timeout' do
        allow(redis).to receive(:hget).with(String, 'clone').and_return '2005-01-1'
        allow(redis).to receive(:smove).with(String, String, String)
        allow(logger).to receive(:log).with(String, String)

        expect(redis).to receive(:smove).with(String, String, vm)
        expect(logger).to receive(:log).with('d', String)

        subject.fail_pending_vm(vm, pool, timeout)
      end

    end
  end


end