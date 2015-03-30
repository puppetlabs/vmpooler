require 'spec_helper'

describe 'Janitor' do
  let(:logger) { double('logger') }
  let(:redis) { double('redis') }
  let(:data_ttl) { 3 } # number of hours to retain
  let(:old_destroy) { '2015-01-30 11:24:30 -0700' }
  let(:fut_destroy) { '3015-01-30 11:24:30 -0700' }

  subject { Vmpooler::Janitor.new(logger, redis, data_ttl) }

  before do
    allow(redis).to receive(:hgetall).with('key1').and_return({'destroy' => old_destroy})
    allow(redis).to receive(:hgetall).with('key2').and_return({'destroy' => old_destroy})
    allow(redis).to receive(:hgetall).with('key3').and_return({'destroy' => Time.now.to_s})
    allow(redis).to receive(:hgetall).with('key4').and_return({'destroy' => Time.now.to_s})
    allow(redis).to receive(:hgetall).with('key5').and_return({'destroy' => fut_destroy})

    allow(redis).to receive(:del)
  end

  describe '#find_stale_vms' do

    context 'has stale vms' do

      it 'has one key' do
        allow(redis).to receive(:keys) {['key1']}

        expect(redis).to receive(:del).with('key1').once
        expect(redis).to receive(:hgetall).with('key1').once
        expect(redis).not_to receive(:hgetall).with('key2')

        subject.find_stale_vms
      end

      it 'has two keys' do
        allow(redis).to receive(:keys) {(%w(key1 key2))}

        expect(redis).to receive(:hgetall).twice
        expect(redis).to receive(:del).with('key1')
        expect(redis).to receive(:del).with('key2')

        subject.find_stale_vms
      end

      it 'has 5 keys and 2 stales' do
        allow(redis).to receive(:keys) {(%w(key1 key2 key3 key4 key5))}


        expect(redis).to receive(:hgetall).exactly(5).times
        expect(redis).to receive(:del).with('key1')
        expect(redis).to receive(:del).with('key2')
        expect(redis).not_to receive(:del).with('key3')
        expect(redis).not_to receive(:del).with('key4')
        expect(redis).not_to receive(:del).with('key5')

        subject.find_stale_vms
      end
    end

    it 'does not have stale vms' do
      allow(redis).to receive(:keys).and_return(['key1'])
      allow(redis).to receive(:hgetall).with('key1') {{'destroy' => Time.now.to_s}}
      allow(redis).to receive(:del).with('key1')

      expect(redis).not_to receive(:del).with('key1')

      subject.find_stale_vms
    end
  end
end