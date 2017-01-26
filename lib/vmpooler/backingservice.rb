# TODO remove dummy for commit history
%w( base vsphere dummy ).each do |lib|
  begin
    require "vmpooler/backingservice/#{lib}"
  rescue LoadError
    require File.expand_path(File.join(File.dirname(__FILE__), 'backingservice', lib))
  end
end
