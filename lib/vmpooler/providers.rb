# frozen_string_literal: true

require 'pathname'

module Vmpooler
  class Providers
    # @param names [Array] - an array of names or string name of a provider
    # @return [Array] - list of provider files loaded
    # ie. ["lib/vmpooler/providers/base.rb", "lib/vmpooler/providers/dummy.rb", "lib/vmpooler/providers/vsphere.rb"]
    def self.load_by_name(names)
      names = Array(names)
      instance = new
      names.map { |name| instance.load_from_gems(name) }.flatten
    end

    # @return [Array] - array of provider files
    # ie. ["lib/vmpooler/providers/base.rb", "lib/vmpooler/providers/dummy.rb", "lib/vmpooler/providers/vsphere.rb"]
    # although these files can come from any gem
    def self.load_all_providers
      new.load_from_gems
    end

    # @return [Array] - returns an array of gem names that contain a provider
    def self.installed_providers
      new.vmpooler_provider_gem_list.map(&:name)
    end

    # @return [Array] returns a list of vmpooler providers gem plugin specs
    def vmpooler_provider_gem_list
      gemspecs.find_all { |spec| File.directory?(File.join(spec.full_gem_path, provider_path)) } + included_lib_dirs
    end

    # Internal: Find any gems containing vmpooler provider plugins and load the main file in them.
    #
    # @return [Array[String]] - a array of provider files
    # @param name [String] - the name of the provider to load
    def load_from_gems(name = nil)
      paths = gem_directories.map do |gem_path|
        # we don't exactly know if the provider name matches the main file name that should be loaded
        # so we use globs to get everything like the name
        # this could mean that vsphere5 and vsphere6 are loaded when only vsphere5 is used
        Dir.glob(File.join(gem_path, "*#{name}*.rb")).sort.each do |file|
          require file
        end
      end
      paths.flatten
    end

    private

    # @return [String] - the relative path to the vmpooler provider dir
    # this is used when searching gems for this path
    def provider_path
      File.join('lib', 'vmpooler', 'providers')
    end

    # Add constants to array to skip over classes, ie. Vmpooler::PoolManager::Provider::Dummy
    def excluded_classes
      []
    end

    # paths to include in the search path
    def included_lib_dirs
      []
    end

    # returns an array of plugin classes by looking in the object space for all loaded classes
    # that start with Vmpooler::PoolManager::Provider
    def plugin_classes
      unless @plugin_classes
        load_plugins
        # weed out any subclasses in the formatter
        klasses = ObjectSpace.each_object(Class).find_all do |c|
          c.name && c.name.split('::').count == 3 && c.name =~ /Vmpooler::PoolManager::Provider/
        end
        @plugin_classes = klasses - excluded_classes || []
      end
      @plugin_classes
    end

    def plugin_map
      @plugin_map ||= Hash[plugin_classes.map { |gem| [gem.send(:name), gem] }]
    end

    # Internal: Retrieve a list of available gem paths from RubyGems.
    #
    # Returns an Array of Pathname objects.
    def gem_directories
      dirs = []
      if rubygems?
        dirs = gemspecs.map do |spec|
          lib_path = File.expand_path(File.join(spec.full_gem_path, provider_path))
          lib_path if File.exist? lib_path
        end + included_lib_dirs
      end
      dirs.reject(&:nil?).uniq
    end

    # Internal: Check if RubyGems is loaded and available.
    #
    # Returns true if RubyGems is available, false if not.
    def rubygems?
      defined? ::Gem
    end

    # Internal: Retrieve a list of available gemspecs.
    #
    # Returns an Array of Gem::Specification objects.
    def gemspecs
      @gemspecs ||= if Gem::Specification.respond_to?(:latest_specs)
                      Gem::Specification.latest_specs
                    else
                      Gem.searcher.init_gemspecs
                    end
    end
  end
end
