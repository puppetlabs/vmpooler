require 'rubygems' unless defined?(Gem)

module Vmpooler
  require 'json'
  require 'open-uri'
  require 'rbvmomi'
  require 'redis'
  require 'sinatra/base'
  require 'time'
  require 'timeout'
  require 'yaml'

  %w( api graphite logger pool_manager vsphere_helper ).each do |lib|
    begin
      require "vmpooler/#{lib}"
    rescue LoadError
      require File.expand_path(File.join(File.dirname(__FILE__), 'vmpooler', lib))
    end
  end
end

