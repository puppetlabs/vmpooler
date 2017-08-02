#!/usr/bin/ruby

require 'rubygems'
require 'rbvmomi'
require 'yaml'

def load_configuration( file_array )
  file_array.each do |file|
    file = File.expand_path( file )

    if File.exists?( file )
      return YAML.load_file( file )
    end
  end

  return false
end

def create_template_deltas( folder )
  config = load_configuration( [ 'vmpooler.yaml', '~/.vmpooler' ] ) || nil

  abort 'No config file (./vmpooler.yaml or ~/.vmpooler) found!' unless config

  vim = RbVmomi::VIM.connect(
    :host     => config[ :providers ][ :vsphere ][ "server" ],
    :user     => config[ :providers ][ :vsphere ][ "username" ],
    :password => config[ :providers ][ :vsphere ][ "password" ],
    :ssl      => true,
    :insecure => true,
  ) or abort "Unable to connect to #{config[ :vsphere ][ "server" ]}!"

  containerView = vim.serviceContent.viewManager.CreateContainerView( {
    :container => vim.serviceContent.rootFolder,
    :recursive => true,
    :type      => [ 'VirtualMachine' ]
  } )

  datacenter = vim.serviceInstance.find_datacenter
  base = datacenter.vmFolder

  case base
    when RbVmomi::VIM::Folder
      base = base.childEntity.find { |f| f.name == folder }
    else
      abort "Unexpected object type encountered (#{base.class}) while finding folder!"
  end

  unless base
    abort "Folder #{ARGV[0]} not found!"
  end

  base.childEntity.each do |vm|
    print vm.name

    begin
      disks = vm.config.hardware.device.grep( RbVmomi::VIM::VirtualDisk )
    rescue
      puts ' !'
      next
    end

    begin
      disks.select { |d| d.backing.parent == nil }.each do |disk|
        linkSpec = {
          :deviceChange => [
            {
              :operation => :remove,
              :device => disk
            },
            {
              :operation => :add,
              :fileOperation => :create,
              :device => disk.dup.tap { |x|
                x.backing = x.backing.dup
                x.backing.fileName = "[#{disk.backing.datastore.name}]"
                x.backing.parent = disk.backing
              }
            }
          ]
        }

        vm.ReconfigVM_Task( :spec => linkSpec ).wait_for_completion
      end

      puts " \u2713"
    rescue
      puts ' !'
    end
  end

  vim.close
end

if ARGV[0]
  create_template_deltas( ARGV[0] )
else
  puts "Usage: #{$0} <folder>"
end
