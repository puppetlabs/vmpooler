require 'spec_helper'

describe 'GenericConnectionPool' do
  let(:metrics) { Vmpooler::DummyStatsd.new }
  let(:metric_prefix) { 'prefix' }
  let(:default_metric_prefix) { 'connectionpool' }
  let(:connection_object) { double('connection') }
  let(:pool_size) { 1 }
  let(:pool_timeout) { 1 }

  subject { Vmpooler::PoolManager::GenericConnectionPool.new(
              metrics: metrics,
              metric_prefix: metric_prefix,
              size: pool_size,
              timeout: pool_timeout
            ) { connection_object }
  }


  describe "#with_metrics" do
    before(:each) do
      expect(subject).not_to be_nil
    end

    context 'When metrics are configured' do
      it 'should emit a gauge metric when the connection is grabbed and released' do
        expect(metrics).to receive(:gauge).with(/\.available/,Integer).exactly(2).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      it 'should emit a timing metric when the connection is grabbed' do
        expect(metrics).to receive(:timing).with(/\.waited/,Integer).exactly(1).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      it 'should emit metrics with the specified prefix' do
        expect(metrics).to receive(:gauge).with(/#{metric_prefix}\./,Integer).at_least(1).times
        expect(metrics).to receive(:timing).with(/#{metric_prefix}\./,Integer).at_least(1).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      context 'Metrix prefix is missing' do
        let(:metric_prefix) { nil }

        it 'should emit metrics with default prefix' do
          expect(metrics).to receive(:gauge).with(/#{default_metric_prefix}\./,Integer).at_least(1).times
          expect(metrics).to receive(:timing).with(/#{default_metric_prefix}\./,Integer).at_least(1).times

          subject.with_metrics do |conn1|
            # do nothing
          end
        end
      end

      context 'Metrix prefix is empty' do
        let(:metric_prefix) { '' }

        it 'should emit metrics with default prefix' do
          expect(metrics).to receive(:gauge).with(/#{default_metric_prefix}\./,Integer).at_least(1).times
          expect(metrics).to receive(:timing).with(/#{default_metric_prefix}\./,Integer).at_least(1).times

          subject.with_metrics do |conn1|
            # do nothing
          end
        end
      end
    end

    context 'When metrics are not configured' do
      let(:metrics) { nil }

      it 'should not emit any metrics' do
        # if any metrics are called it would result in a method error on Nil.

        subject.with_metrics do |conn1|
          # do nothing
        end
      end
    end

  end
end
