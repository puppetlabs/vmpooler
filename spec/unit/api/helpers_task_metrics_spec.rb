# frozen_string_literal: true

require 'spec_helper'
require 'date'
require 'socket'

class TaskMetricsHelpers
  include Vmpooler::API::Helpers
end

describe Vmpooler::API::Helpers do
  subject { TaskMetricsHelpers.new }

  let(:redis) { MockRedis.new }
  let(:day1) { '2024-05-01' }
  let(:day2) { '2024-05-02' }

  def seed(task, date_str, entries)
    entries.each { |field, seconds| redis.hset("vmpooler__#{task}__#{date_str}", field, seconds) }
  end

  describe '#get_task_metrics' do
    it 'returns zeros when nothing was recorded that day' do
      expect(subject.get_task_metrics(redis, 'clone', day1)).to eq(
        duration: { average: 0, min: 0, max: 0, total: 0 },
        count: { total: 0 }
      )
    end

    it 'totals and averages the recorded durations' do
      seed('clone', day1, 'pool1:h1' => 2, 'pool1:h2' => 4, 'pool2:h3' => 6)

      metrics = subject.get_task_metrics(redis, 'clone', day1)

      expect(metrics[:count]).to eq(total: 3)
      expect(metrics[:duration]).to eq(total: 12.0, average: 4.0, min: 2.0, max: 6.0)
    end

    it 'only reads the day it was asked about' do
      seed('clone', day1, 'pool1:h1' => 2)
      seed('clone', day2, 'pool1:h2' => 30)

      expect(subject.get_task_metrics(redis, 'clone', day1)[:duration][:total]).to eq(2.0)
    end

    context 'by pool' do
      before { seed('clone', day1, 'pool1:h1' => 2, 'pool1:h2' => 4, 'pool2:h3' => 6, 'h4' => 8) }

      let(:metrics) { subject.get_task_metrics(redis, 'clone', day1, bypool: true) }

      it 'counts the entries in each pool' do
        expect(metrics[:count][:pool]).to eq(
          'pool1' => { total: 2 }, 'pool2' => { total: 1 }, 'unknown' => { total: 1 }
        )
      end

      it 'gives the duration summary of each pool' do
        expect(metrics[:duration][:pool]['pool1']).to eq(total: 6.0, average: 3.0, min: 2.0, max: 4.0)
        expect(metrics[:duration][:pool]['pool2']).to eq(total: 6.0, average: 6.0, min: 6.0, max: 6.0)
      end

      it 'puts an entry without a pool under "unknown"' do
        expect(metrics[:duration][:pool]['unknown']).to include(total: 8.0, min: 8.0, max: 8.0)
      end

      it 'still gives the overall duration' do
        expect(metrics[:duration]).to include(total: 20.0, average: 5.0, min: 2.0, max: 8.0)
      end
    end

    it 'can return one part only' do
      seed('clone', day1, 'pool1:h1' => 2)

      expect(subject.get_task_metrics(redis, 'clone', day1, only: 'count')).to eq(count: { total: 1 })
    end
  end

  describe '#get_task_summary' do
    let(:from) { Date.parse(day1) }
    let(:to) { Date.parse(day2) }

    before do
      seed('clone', day1, 'pool1:h1' => 2, 'pool1:h2' => 4)
      seed('clone', day2, 'pool1:h3' => 10, 'pool2:h4' => 6)
    end

    it 'lists each day in the range' do
      summary = subject.get_task_summary(redis, 'clone', from, to)

      expect(summary[:daily].map { |d| d[:date] }).to eq([day1, day2])
      expect(summary[:daily][0][:clone][:count]).to eq(total: 2)
      expect(summary[:daily][1][:clone][:count]).to eq(total: 2)
    end

    it 'adds up the counts and durations over the range' do
      summary = subject.get_task_summary(redis, 'clone', from, to)

      expect(summary[:clone][:count][:total]).to eq(4)
      expect(summary[:clone][:duration][:total]).to eq(22.0)
    end

    it 'gives the min, max and average duration over the range' do
      summary = subject.get_task_summary(redis, 'clone', from, to)

      expect(summary[:clone][:duration]).to include(min: 2.0, max: 10.0)
      expect(summary[:clone][:duration][:average]).to be_a(Numeric)
    end

    it 'handles a range with no data' do
      summary = subject.get_task_summary(redis, 'clone', Date.parse('2020-01-01'), Date.parse('2020-01-02'))

      expect(summary[:clone][:count][:total]).to eq(0)
      expect(summary[:daily].length).to eq(2)
    end

    context 'by pool' do
      let(:summary) { subject.get_task_summary(redis, 'clone', from, to, bypool: true) }

      it 'adds up the counts of each pool' do
        expect(summary[:clone][:count][:pool]['pool1'][:total]).to eq(3)
        expect(summary[:clone][:count][:pool]['pool2'][:total]).to eq(1)
      end

      it 'adds up the durations of each pool and gives its min, max and average' do
        pool1 = summary[:clone][:duration][:pool]['pool1']

        expect(pool1[:total]).to eq(16.0)
        expect(pool1[:min]).to eq(2.0)
        expect(pool1[:max]).to eq(10.0)
        expect(pool1[:average]).to eq(6.5)
        expect(summary[:clone][:duration][:pool]['pool2']).to include(total: 6.0, min: 6.0, max: 6.0, average: 6.0)
      end
    end
  end

  describe '#open_socket' do
    let(:socket) { instance_double(TCPSocket, close: nil) }

    it 'connects to port 22 with a 1 second timeout by default, and closes the socket' do
      expect(TCPSocket).to receive(:new).with('vm1', 22, connect_timeout: 1).and_return(socket)

      subject.open_socket('vm1')

      expect(socket).to have_received(:close)
    end

    it 'adds the domain to the host name' do
      expect(TCPSocket).to receive(:new).with('vm1.example.com', 22, connect_timeout: 1).and_return(socket)

      subject.open_socket('vm1', 'example.com')
    end

    it 'uses the port and timeout it is given' do
      expect(TCPSocket).to receive(:new).with('vm1.example.com', 3389, connect_timeout: 5).and_return(socket)

      subject.open_socket('vm1', 'example.com', 5, 3389)
    end

    it 'gives the socket to the block' do
      allow(TCPSocket).to receive(:new).and_return(socket)

      yielded = nil
      subject.open_socket('vm1') { |sock| yielded = sock }

      expect(yielded).to be(socket)
    end

    it 'closes the socket even when the block raises' do
      allow(TCPSocket).to receive(:new).and_return(socket)

      expect { subject.open_socket('vm1') { raise 'boom' } }.to raise_error('boom')
      expect(socket).to have_received(:close)
    end

    it 'does not hide a connection error' do
      allow(TCPSocket).to receive(:new).and_raise(Errno::ECONNREFUSED)

      expect { subject.open_socket('vm1') }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
