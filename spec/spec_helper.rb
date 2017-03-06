require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end
require 'helpers'
require 'rbvmomi_helper'
require 'rbvmomi'
require 'rspec'
require 'vmpooler'
require 'redis'
require 'vmpooler/statsd'
