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

end