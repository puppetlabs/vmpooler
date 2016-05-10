require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end
require 'helpers'
require 'rbvmomi'
require 'rspec'
require 'vmpooler'
