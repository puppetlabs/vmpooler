# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'climate_control'

describe Vmpooler::Logger do
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @file = File.join(dir, 'vmpooler.log')
      example.run
    end
  end

  let(:logger) { described_class.new(@file) }

  it 'logs to /var/log/vmpooler.log unless told otherwise' do
    expect(described_class.new.instance_variable_get(:@file)).to eq('/var/log/vmpooler.log')
  end

  it 'appends a timestamped line to the file' do
    now = Time.new(2024, 5, 1, 13, 4, 5)
    allow(Time).to receive(:new).and_return(now)

    logger.log('s', 'pool1 is ready')

    expect(File.read(@file)).to eq("[2024-05-01 13:04:05] pool1 is ready\n")
  end

  it 'keeps what was logged before' do
    logger.log('s', 'first')
    logger.log('d', 'second')

    expect(File.readlines(@file).map { |line| line.sub(/\A\[[^\]]+\] /, '').chomp }).to eq(%w[first second])
  end

  it 'prints nothing in debug mode being off' do
    ClimateControl.modify(VMPOOLER_DEBUG: nil) do
      expect { logger.log('s', 'quiet') }.not_to output.to_stdout
    end
  end

  it 'also prints the line when VMPOOLER_DEBUG is set' do
    ClimateControl.modify(VMPOOLER_DEBUG: 'true') do
      expect { logger.log('s', 'loud') }.to output(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] loud/).to_stdout
    end
  end
end
