module Vmpooler
  class API
  class Dashboard < Sinatra::Base
    get '/dashboard/stats/vmpooler/pool/?' do
      content_type :json

      result = {}

      Vmpooler::API.settings.config[:pools].each do |pool|
        result[pool['name']] ||= {}
        result[pool['name']]['size'] = pool['size']
        result[pool['name']]['ready'] = $redis.scard('vmpooler__ready__' + pool['name'])
      end

      if params[:history]
        if Vmpooler::API.settings.config[:graphite]['server']
          history ||= {}

          begin
            buffer = open(
              'http://' + Vmpooler::API.settings.config[:graphite]['server'] + '/render?target=' + Vmpooler::API.settings.config[:graphite]['prefix'] + '.ready.*&from=-1hour&format=json'
            ).read
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
        if Vmpooler::API.settings.config[:graphite]['server']
          begin
            buffer = open(
              'http://' + Vmpooler::API.settings.config[:graphite]['server'] + '/render?target=' + Vmpooler::API.settings.config[:graphite]['prefix'] + '.running.*&from=-1hour&format=json'
            ).read
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
