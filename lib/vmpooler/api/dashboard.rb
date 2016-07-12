module Vmpooler
  class API
  class Dashboard < Sinatra::Base

    # handle to the App's configuration information
    def config
      @config ||= Vmpooler::API.settings.config
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
        return false unless config[:graphs]['prefix']
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
    def graph_link(target = "")
      return "" unless graph_url
      graph_url + target
    end


    get '/dashboard/stats/vmpooler/pool/?' do
      content_type :json
      result = {}

      Vmpooler::API.settings.config[:pools].each do |pool|
        result[pool['name']] ||= {}
        result[pool['name']]['size'] = pool['size']
        result[pool['name']]['ready'] = Vmpooler::API.settings.redis.scard('vmpooler__ready__' + pool['name'])
      end

      if params[:history]
        if graph_url
          history ||= {}

          begin
            buffer = open(graph_link('.qready.*&from=-1hour&format=json')).read
            history = JSON.parse(buffer)

            history.each do |pool|
              if pool['target'] =~ /.*\.(.*)$/
                pool['name'] = Regexp.last_match[1]

                if result[pool['name']]
                  pool['last'] = result[pool['name']]['size']
                  result[pool['name']]['history'] ||= Array.new

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
          rescue
          end
        else
          Vmpooler::API.settings.config[:pools].each do |pool|
            result[pool['name']] ||= {}
            result[pool['name']]['history'] = [Vmpooler::API.settings.redis.scard('vmpooler__ready__' + pool['name'])]
          end
        end
      end
      JSON.pretty_generate(result)
    end

    get '/dashboard/stats/vmpooler/running/?' do
      content_type :json
      result = {}

      Vmpooler::API.settings.config[:pools].each do |pool|
        running = Vmpooler::API.settings.redis.scard('vmpooler__running__' + pool['name'])
        pool['major'] = Regexp.last_match[1] if pool['name'] =~ /^(\w+)\-/
        result[pool['major']] ||= {}
        result[pool['major']]['running'] = result[pool['major']]['running'].to_i + running.to_i
      end

      if params[:history]
        if graph_url
          begin
            buffer = open(graph_link('.running.*&from=-1hour&format=json')).read
            JSON.parse(buffer).each do |pool|
              if pool['target'] =~ /.*\.(.*)$/
                pool['name'] = Regexp.last_match[1]
                pool['major'] = Regexp.last_match[1] if pool['name'] =~ /^(\w+)\-/
                result[pool['major']]['history'] ||= Array.new

                for i in 0..pool['datapoints'].length
                  if
                    pool['datapoints'][i] &&
                    pool['datapoints'][i][0]
                    pool['last'] = pool['datapoints'][i][0]
                    result[pool['major']]['history'][i] ||= 0
                    result[pool['major']]['history'][i] = result[pool['major']]['history'][i].to_i + pool['datapoints'][i][0].to_i
                  else
                    result[pool['major']]['history'][i] = result[pool['major']]['history'][i].to_i + pool['last'].to_i
                  end
                end
              end
            end
          rescue
          end
        end
      end
      JSON.pretty_generate(result)
    end
  end
  end
end
