require 'spec_helper'
require 'time'

describe 'Pool Manager' do
  let(:logger) { double('logger') }
  let(:redis) { double('redis') }
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:config) { {} }
  let(:pool) { 'pool1' }
  let(:vm) { 'vm1' }
  let(:timeout) { 5 }
  let(:host) { double('host') }

  subject { Vmpooler::PoolManager.new(config, logger, redis, metrics) }

  describe '#_create_vm_snapshot' do
    let(:snapshot_manager) { 'snapshot_manager' }
    let(:pool_helper) { double('snapshot_manager') }
    let(:backingservice) { {snapshot_manager => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
    end

    context '(valid host)' do
      let(:vm_host) { double('vmhost') }

      it 'creates a snapshot' do
        expect(backingservice).to receive(:get_vm).and_return vm_host
        expect(logger).to receive(:log)
        expect(vm_host).to receive_message_chain(:CreateSnapshot_Task, :wait_for_completion)
        expect(redis).to receive(:hset).with('vmpooler__vm__testvm', 'snapshot:testsnapshot', Time.now.to_s)
        expect(logger).to receive(:log)

        subject._create_vm_snapshot('testvm', 'testsnapshot', backingservice)
      end
    end
  end

  describe '#_revert_vm_snapshot' do
    let(:snapshot_manager) { 'snapshot_manager' }
    let(:pool_helper) { double('snapshot_manager') }
    let(:backingservice) { {snapshot_manager => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
    end

    context '(valid host)' do
      let(:vm_host) { double('vmhost') }
      let(:vm_snapshot) { double('vmsnapshot') }

      it 'reverts a snapshot' do
        expect(backingservice).to receive(:get_vm).and_return vm_host
        expect(backingservice).to receive(:find_snapshot).and_return vm_snapshot
        expect(logger).to receive(:log)
        expect(vm_snapshot).to receive_message_chain(:RevertToSnapshot_Task, :wait_for_completion)
        expect(logger).to receive(:log)

        subject._revert_vm_snapshot('testvm', 'testsnapshot', backingservice)
      end
    end
  end

  describe '#_check_snapshot_queue' do
    let(:pool_helper) { double('pool') }
    let(:backingservice) { {pool => pool_helper} }

    before do
      expect(subject).not_to be_nil
      $backingservice = backingservice
    end

    it 'checks appropriate redis queues' do
      expect(redis).to receive(:spop).with('vmpooler__tasks__snapshot')
      expect(redis).to receive(:spop).with('vmpooler__tasks__snapshot-revert')

      subject._check_snapshot_queue(backingservice)
    end
  end
end
