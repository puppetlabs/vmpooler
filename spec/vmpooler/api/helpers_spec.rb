require 'spec_helper'

# A class for testing purposes that includes the Helpers.
# this is impersonating V1's `helpers do include Helpers end`
#
# This is the subject used throughout the test file.
#
class TestHelpers
  include Vmpooler::API::Helpers
end

describe Vmpooler::API::Helpers do

  subject { TestHelpers.new }

  describe '#hostname_shorten' do
    [
        ['example.com', 'not-example.com', 'example.com'],
        ['example.com', 'example.com', 'example.com'],
        ['sub.example.com', 'example.com', 'sub'],
        ['example.com', nil, 'example.com']
    ].each do |hostname, domain, expected|
      it { expect(subject.hostname_shorten(hostname, domain)).to eq expected }
    end
  end

  describe '#validate_date_str' do
    [
        ['2015-01-01', true],
        [nil, false],
        [false, false],
        [true, false],
        ['01-01-2015', false],
        ['1/1/2015', false]
    ].each do |date, expected|
      it { expect(subject.validate_date_str(date)).to eq expected }
    end
  end

  describe '#mean' do
    [
        [[1, 2, 3, 4], 2.5],
        [[1], 1],
        [[nil], 0],
        [[], 0]
    ].each do |list, expected|
      it "returns #{expected.inspect} for #{list.inspect}" do
        expect(subject.mean(list)).to eq expected
      end
    end
  end

  describe '#get_task_times' do
    let(:redis) { double('redis') }
    [
        ['task1', '2014-01-01', [1, 2, 3, 4], [1.0, 2.0, 3.0, 4.0]],
        ['task1', 'some date', [], []],
        ['task1', 'date', [2.2], [2.2]],
        ['task1', 'date', [2.2, 3, 3.0], [2.2, 3.0, 3.0]]
    ].each do |task, date, time_list, expected|
      it "returns #{expected.inspect} for task #{task.inspect}@#{date.inspect}" do
        allow(redis).to receive(:hvals).and_return time_list
        expect(subject.get_task_times(redis, task, date)).to eq expected
      end
    end
  end

  describe '#get_capacity_metrics' do
    let(:redis) { double('redis') }

    it 'adds up pools correctly' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 1

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 2, total: 10, percent: 20.0})
    end

    it 'handles 0 from redis' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 0

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 10, percent: 10.0})
    end

    it 'handles 0 size' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 0}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 0

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 5, percent: 20.0})
    end

    it 'handles empty pool array' do
      expect(subject.get_capacity_metrics([], redis)).to eq({current: 0, total: 0, percent: 0})
    end
  end

  describe '#get_queue_metrics' do
    let(:redis) { double('redis') }

    it 'handles empty pool array' do
      allow(redis).to receive(:scard).and_return 0
      allow(redis).to receive(:get).and_return 0

      expect(subject.get_queue_metrics([], redis)).to eq({pending: 0, cloning: 0, booting: 0, ready: 0, running: 0, completed: 0, total: 0})
    end

    it 'adds pool queues correctly' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      pools.each do |p|
        %w(pending ready running completed).each do |action|
          allow(redis).to receive(:scard).with('vmpooler__' + action + '__' + p['name']).and_return 1
        end
      end
      allow(redis).to receive(:get).and_return 1

      expect(subject.get_queue_metrics(pools, redis)).to eq({pending: 2, cloning: 1, booting: 1, ready: 2, running: 2, completed: 2, total: 8})
    end

    it 'sets booting to 0 when negative calculation' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      pools.each do |p|
        %w(pending ready running completed).each do |action|
          allow(redis).to receive(:scard).with('vmpooler__' + action + '__' + p['name']).and_return 1
        end
      end
      allow(redis).to receive(:get).and_return 5

      expect(subject.get_queue_metrics(pools, redis)).to eq({pending: 2, cloning: 5, booting: 0, ready: 2, running: 2, completed: 2, total: 8})
    end
  end

  describe '#get_tag_metrics' do
    let(:redis) { double('redis') }

    it 'returns basic tag metrics' do
      allow(redis).to receive(:hgetall).with('vmpooler__tag__2015-01-01').and_return({"abcdefghijklmno:tag" => "value"})

      expect(subject.get_tag_metrics(redis, '2015-01-01')).to eq({"tag" => {"value"=>1, "total"=>1}})
    end

    it 'calculates tag totals' do
      allow(redis).to receive(:hgetall).with('vmpooler__tag__2015-01-01').and_return({"abcdefghijklmno:tag" => "value", "pqrstuvwxyz12345:tag" => "another_value"})

      expect(subject.get_tag_metrics(redis, '2015-01-01')).to eq({"tag"=>{"value"=>1, "total"=>2, "another_value"=>1}})
    end
  end

end
