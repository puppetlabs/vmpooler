%w(base dummy vsphere).each do |lib|
  begin
    require "vmpooler/providers/#{lib}"
  rescue LoadError
    require File.expand_path(File.join(File.dirname(__FILE__), 'providers', lib))
  end
end
