# frozen_string_literal: true

module Vmpooler
  class API
    class Dashboard < Sinatra::Base
      helpers do
        include Vmpooler::API::Helpers
      end

      # handle to the App's configuration information
      def config
        @config ||= Vmpooler::API.settings.config
      end

      def backend
        Vmpooler::API.settings.redis
      end

      # configuration setting for server hosting graph URLs to view
      def graph_server
        return @graph_server if @graph_server

        if config[:graphs]
          return false unless config[:graphs]['server']

          @graph_server = config[:graphs]['server']
        elsif config[:graphite]
          return false unless config[:graphite]['server']

          @graph_server = config[:graphite]['server']
        else
          false
        end
      end

      # configuration setting for URL prefix for graphs to view
      def graph_prefix
        return @graph_prefix if @graph_prefix

        if config[:graphs]
          return 'vmpooler' unless config[:graphs]['prefix']

          @graph_prefix = config[:graphs]['prefix']
        elsif config[:graphite]
          return false unless config[:graphite]['prefix']

          @graph_prefix = config[:graphite]['prefix']
        else
          false
        end
      end

      # what is the base URL for viewable graphs?
      def graph_url
        return false unless graph_server && graph_prefix

        @graph_url ||= "http://#{graph_server}/render?target=#{graph_prefix}"
      end

      # return a full URL to a viewable graph for a given metrics target (graphite syntax)
      def graph_link(target = '')
        return '' unless graph_url

        graph_url + target
      end


      get '/dashboard/stats/vmpooler/pool/?' do
        content_type :json
        result = {}

        pools = Vmpooler::API.settings.config[:pools]
        ready_hash = get_list_across_pools_redis_scard(pools, 'vmpooler__ready__', backend)

        pools.each do |pool|
          result[pool['name']] ||= {}
          result[pool['name']]['size'] = pool['size']
          result[pool['name']]['ready'] = ready_hash[pool['name']]
        end

        if params[:history]
          if graph_url
            history ||= {}

            begin
              buffer = URI.parse(graph_link('.ready.*&from=-1hour&format=json')).read
              history = JSON.parse(buffer)

              history.each do |pool|
                if pool['target'] =~ /.*\.(.*)$/
                  pool['name'] = Regexp.last_match[1]

                  if result[pool['name']]
                    pool['last'] = result[pool['name']]['size']
                    result[pool['name']]['history'] ||= []

                    pool['datapoints'].each do |metric|
                      8.times do |_n|
                        if metric[0]
                          pool['last'] = metric[0].to_i
                          result[pool['name']]['history'].push(metric[0].to_i)
                        else
                          result[pool['name']]['history'].push(pool['last'])
                        end
                      end
                    end
                  end
                end
              end
            rescue StandardError
            end
          else
            pools.each do |pool|
              result[pool['name']] ||= {}
              result[pool['name']]['history'] = [ready_hash[pool['name']]]
            end
          end
        end
        JSON.pretty_generate(result)
      end

      get '/dashboard/stats/vmpooler/running/?' do
        content_type :json
        result = {}

        pools = Vmpooler::API.settings.config[:pools]
        running_hash = get_list_across_pools_redis_scard(pools, 'vmpooler__running__', backend)

        pools.each do |pool|
          running = running_hash[pool['name']]
          pool['major'] = Regexp.last_match[1] if pool['name'] =~ /^(\w+)-/
          result[pool['major']] ||= {}
          result[pool['major']]['running'] = result[pool['major']]['running'].to_i + running.to_i
        end

        if params[:history] && graph_url
          begin
            buffer = URI.parse(graph_link('.running.*&from=-1hour&format=json')).read
            JSON.parse(buffer).each do |pool|
              if pool['target'] =~ /.*\.(.*)$/
                pool['name'] = Regexp.last_match[1]
                pool['major'] = Regexp.last_match[1] if pool['name'] =~ /^(\w+)-/
                result[pool['major']]['history'] ||= []

                for i in 0..pool['datapoints'].length
                  if pool['datapoints'][i] && pool['datapoints'][i][0]
                    pool['last'] = pool['datapoints'][i][0]
                    result[pool['major']]['history'][i] ||= 0
                    result[pool['major']]['history'][i] = result[pool['major']]['history'][i].to_i + pool['datapoints'][i][0].to_i
                  else
                    result[pool['major']]['history'][i] = result[pool['major']]['history'][i].to_i + pool['last'].to_i
                  end
                end
              end
            end
          rescue StandardError
          end
        end
        JSON.pretty_generate(result)
      end
    end
  end
end
