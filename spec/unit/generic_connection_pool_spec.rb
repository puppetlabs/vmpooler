require 'spec_helper'

describe 'GenericConnectionPool' do
  let(:metrics) { Vmpooler::Metrics::DummyStatsd.new }
  let(:connpool_type) { 'test_connection_pool' }
  let(:connpool_provider) { 'testprovider' }
  let(:default_connpool_type) { 'connectionpool' }
  let(:connection_object) { double('connection') }
  let(:pool_size) { 1 }
  let(:pool_timeout) { 1 }

  subject { Vmpooler::PoolManager::GenericConnectionPool.new(
              metrics: metrics,
              connpool_type: connpool_type,
              connpool_provider: connpool_provider,
              size: pool_size,
              timeout: pool_timeout
            ) { connection_object }
  }

  describe "When consuming a pool object" do
    let(:pool_size) { 1 }
    let(:pool_timeout) { 1 }
    let(:connection_object) {{
      connection: 'connection'
    }}

    it 'should error out when connection pool could not establish no nothing' do
      newsub = Vmpooler.redis_connection_pool("foo,bar", "1234", "fuba", 1, 1, metrics, 0)
      expect { newsub.with_metrics do |conn_pool_object|
        conn_pool_object.srem('foo', "bar")
      end }.to raise_error Redis::CannotConnectError
    end

    it 'should return a connection object when grabbing one from the pool' do
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
      end
    end

    it 'should return the same connection object when calling the pool multiple times' do
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
      end
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
      end
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
      end
    end

    it 'should preserve connection state across mulitple pool calls' do
      new_connection = 'new_connection'
      # Ensure the connection is not modified
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
        expect(conn_pool_object[:connection]).to_not eq(new_connection)
        # Change the connection
        conn_pool_object[:connection] = new_connection
      end
      # Ensure the connection is modified
      subject.with_metrics do |conn_pool_object|
        expect(conn_pool_object).to be(connection_object)
        expect(conn_pool_object[:connection]).to eq(new_connection)
      end
    end
  end

  describe "#with_metrics" do
    before(:each) do
      expect(subject).not_to be_nil
    end

    context 'When metrics are configured' do
      it 'should emit a gauge metric when the connection is grabbed and released' do
        expect(metrics).to receive(:gauge).with(/connection_available/,Integer).exactly(2).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      it 'should emit a timing metric when the connection is grabbed' do
        expect(metrics).to receive(:timing).with(/connection_waited/,Integer).exactly(1).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      it 'should emit metrics with the specified prefix' do
        expect(metrics).to receive(:gauge).with(/#{connpool_type}\./,Integer).at_least(1).times
        expect(metrics).to receive(:timing).with(/#{connpool_type}\./,Integer).at_least(1).times

        subject.with_metrics do |conn1|
          # do nothing
        end
      end

      context 'Metrix prefix is missing' do
        let(:connpool_type) { nil }

        it 'should emit metrics with default prefix' do
          expect(metrics).to receive(:gauge).with(/#{default_connpool_type}\./,Integer).at_least(1).times
          expect(metrics).to receive(:timing).with(/#{default_connpool_type}\./,Integer).at_least(1).times

          subject.with_metrics do |conn1|
            # do nothing
          end
        end
      end

      context 'Metrix prefix is empty' do
        let(:connpool_type) { '' }

        it 'should emit metrics with default prefix' do
          expect(metrics).to receive(:gauge).with(/#{default_connpool_type}\./,Integer).at_least(1).times
          expect(metrics).to receive(:timing).with(/#{default_connpool_type}\./,Integer).at_least(1).times

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
