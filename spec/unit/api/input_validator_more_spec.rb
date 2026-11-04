# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/api/input_validator'

describe Vmpooler::API::InputValidator do
  let(:validator) { Class.new { include Vmpooler::API::InputValidator }.new }

  describe '#validate_token_format' do
    it 'accepts letters, digits, dashes and underscores' do
      expect(validator.validate_token_format('abc-123_XYZ')).to be true
    end

    it 'wants a token' do
      expect(validator.validate_token_format(nil)).to eq('ok' => false, 'error' => 'Token is required')
      expect(validator.validate_token_format('')).to eq('ok' => false, 'error' => 'Token is required')
    end

    it 'refuses a token longer than 64 characters' do
      expect(validator.validate_token_format('a' * 64)).to be true
      expect(validator.validate_token_format('a' * 65)).to eq('ok' => false, 'error' => 'Token too long')
    end

    it 'refuses other characters' do
      ['abc def', 'abc!', 'a/b', "abc\n"].each do |token|
        expect(validator.validate_token_format(token)).to eq('ok' => false, 'error' => 'Invalid token format')
      end
    end
  end

  describe '#validate_reason' do
    it 'accepts no reason' do
      expect(validator.validate_reason(nil)).to be true
      expect(validator.validate_reason('')).to be true
    end

    it 'accepts a plain reason' do
      expect(validator.validate_reason('testing the new build')).to be true
    end

    it 'refuses a reason longer than 500 characters' do
      expect(validator.validate_reason('a' * 500)).to be true
      expect(validator.validate_reason('a' * 501)).to eq('ok' => false, 'error' => 'Reason too long')
    end

    it 'refuses markup and quote characters' do
      ['<script>', 'say "hi"', "it's", 'a > b'].each do |reason|
        expect(validator.validate_reason(reason)).to eq('ok' => false, 'error' => 'Reason contains invalid characters')
      end
    end
  end

  describe '#sanitize_json_body with arrays inside the object' do
    it 'counts the depth of nested arrays' do
      expect(validator.sanitize_json_body('{"a": [[1, 2], [3]]}')).to eq('a' => [[1, 2], [3]])
    end

    it 'refuses arrays nested too deeply' do
      body = '{"a": [[[[[[1]]]]]]}'

      expect(validator.sanitize_json_body(body)).to eq('ok' => false, 'error' => 'Request body too complex')
    end
  end
end
