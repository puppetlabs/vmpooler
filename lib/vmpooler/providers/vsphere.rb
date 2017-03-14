module Vmpooler
  class PoolManager
    class Provider
      class VSphere  < Vmpooler::PoolManager::Provider::Base

        def initialize(options)
         super(options)
        end

        def name
          'vsphere'
        end

      end
    end
  end
end
