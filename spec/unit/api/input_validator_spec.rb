# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'vmpooler/api/input_validator'

describe Vmpooler::API::InputValidator do
  let(:test_class) do
    Class.new do
      include Vmpooler::API::InputValidator
    end
  end
  let(:validator) { test_class.new }

  describe '#validate_hostname' do
    it 'accepts valid hostnames' do
      expect(validator.validate_hostname('test-host.example.com')).to be true
      expect(validator.validate_hostname('host123')).to be true
    end

    it 'rejects invalid hostnames' do
      result = validator.validate_hostname('invalid_host!')
      expect(result['ok']).to be false
      expect(result['error']).to include('Invalid hostname format')
    end

    it 'rejects hostnames that are too long' do
      long_hostname = 'a' * 300
      result = validator.validate_hostname(long_hostname)
      expect(result['ok']).to be false
      expect(result['error']).to include('too long')
    end

    it 'rejects empty hostnames' do
      result = validator.validate_hostname('')
      expect(result['ok']).to be false
      expect(result['error']).to include('required')
    end
  end

  describe '#validate_pool_name' do
    it 'accepts valid pool names' do
      expect(validator.validate_pool_name('centos-7-x86_64')).to be true
      expect(validator.validate_pool_name('ubuntu-2204')).to be true
    end

    it 'rejects invalid pool names' do
      result = validator.validate_pool_name('invalid pool!')
      expect(result['ok']).to be false
      expect(result['error']).to include('Invalid pool name format')
    end

    it 'rejects pool names that are too long' do
      result = validator.validate_pool_name('a' * 150)
      expect(result['ok']).to be false
      expect(result['error']).to include('too long')
    end
  end

  describe '#validate_tag' do
    it 'accepts valid tags' do
      expect(validator.validate_tag('project', 'test-123')).to be true
      expect(validator.validate_tag('owner', 'user@example.com')).to be true
    end

    it 'rejects tags with invalid keys' do
      result = validator.validate_tag('invalid key!', 'value')
      expect(result['ok']).to be false
      expect(result['error']).to include('Invalid tag key format')
    end

    it 'rejects tags with invalid characters in value' do
      result = validator.validate_tag('key', 'value<script>')
      expect(result['ok']).to be false
      expect(result['error']).to include('invalid characters')
    end

    it 'rejects tags that are too long' do
      result = validator.validate_tag('key', 'a' * 300)
      expect(result['ok']).to be false
      expect(result['error']).to include('too long')
    end
  end

  describe '#validate_vm_count' do
    it 'accepts valid VM counts' do
      expect(validator.validate_vm_count(5)).to eq(5)
      expect(validator.validate_vm_count('10')).to eq(10)
    end

    it 'rejects counts less than 1' do
      result = validator.validate_vm_count(0)
      expect(result['ok']).to be false
      expect(result['error']).to include('at least 1')
    end

    it 'rejects counts greater than 100' do
      result = validator.validate_vm_count(150)
      expect(result['ok']).to be false
      expect(result['error']).to include('at most 100')
    end

    it 'rejects non-integer values' do
      result = validator.validate_vm_count('abc')
      expect(result['ok']).to be false
      expect(result['error']).to include('valid integer')
    end
  end

  describe '#validate_disk_size' do
    it 'accepts valid disk sizes' do
      expect(validator.validate_disk_size(50)).to eq(50)
      expect(validator.validate_disk_size('100')).to eq(100)
    end

    it 'rejects sizes less than 1' do
      result = validator.validate_disk_size(0)
      expect(result['ok']).to be false
    end

    it 'rejects sizes greater than 2048' do
      result = validator.validate_disk_size(3000)
      expect(result['ok']).to be false
    end
  end

  describe '#validate_lifetime' do
    it 'accepts valid lifetimes' do
      expect(validator.validate_lifetime(24)).to eq(24)
      expect(validator.validate_lifetime('48')).to eq(48)
    end

    it 'rejects lifetimes greater than 168 hours (1 week)' do
      result = validator.validate_lifetime(200)
      expect(result['ok']).to be false
      expect(result['error']).to include('at most 168')
    end
  end

  describe '#sanitize_json_body' do
    it 'parses valid JSON' do
      result = validator.sanitize_json_body('{"key": "value"}')
      expect(result).to eq('key' => 'value')
    end

    it 'rejects invalid JSON' do
      result = validator.sanitize_json_body('{invalid}')
      expect(result['ok']).to be false
      expect(result['error']).to include('Invalid JSON')
    end

    it 'rejects non-object JSON' do
      result = validator.sanitize_json_body('["array"]')
      expect(result['ok']).to be false
      expect(result['error']).to include('must be a JSON object')
    end

    it 'rejects deeply nested JSON' do
      deep_json = '{"a":{"b":{"c":{"d":{"e":{"f":"too deep"}}}}}}'
      result = validator.sanitize_json_body(deep_json)
      expect(result['ok']).to be false
      expect(result['error']).to include('too complex')
    end

    it 'rejects bodies that are too large' do
      large_json = '{"data":"' + ('a' * 20000) + '"}'
      result = validator.sanitize_json_body(large_json)
      expect(result['ok']).to be false
      expect(result['error']).to include('too large')
    end
  end

  describe '#validation_error?' do
    it 'returns true for error responses' do
      error = { 'ok' => false, 'error' => 'test error' }
      expect(validator.validation_error?(error)).to be true
    end

    it 'returns false for successful responses' do
      expect(validator.validation_error?(true)).to be false
      expect(validator.validation_error?(5)).to be false
    end
  end
end
