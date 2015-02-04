module Vmpooler
  class API
    def initialize
      # Load the configuration file
      config_file = File.expand_path('vmpooler.yaml')
      $config = YAML.load_file(config_file)

      $config[:uptime] = Time.now

      # Set some defaults
      $config[:redis] ||= Hash.new
      $config[:redis]['server'] ||= 'localhost'

      if ($config[:graphite]['server'])
        $config[:graphite]['prefix'] ||= 'vmpooler'
      end

      # Connect to Redis
      $redis = Redis.new(:host => $config[:redis]['server'])
    end

    def execute!
      my_app = Sinatra.new {

        set :environment, 'production'

        helpers do
          def hostname_shorten hostname
            if ( $config[:config]['domain'] and hostname =~ /^\w+\.#{$config[:config]['domain']}$/ )
              hostname = hostname[/[^\.]+/]
            end

            hostname
          end
        end

        get '/' do
          erb :dashboard, locals: {
            site_name: $config[:config]['site_name'] || '<b>vmpooler</b>',
          }
        end

        get '/dashboard/stats/vmpooler/numbers/?' do
          result = Hash.new
          result['pending'] = 0
          result['cloning'] = 0
          result['booting'] = 0
          result['ready'] = 0
          result['running'] = 0
          result['completed'] = 0

          $config[:pools].each do |pool|
            result['pending'] += $redis.scard( 'vmpooler__pending__' + pool['name'] )
            result['ready'] += $redis.scard( 'vmpooler__ready__' + pool['name'] )
            result['running'] += $redis.scard( 'vmpooler__running__' + pool['name'] )
            result['completed'] += $redis.scard( 'vmpooler__completed__' + pool['name'] )
          end

          result['cloning'] = $redis.get( 'vmpooler__tasks__clone' )
          result['booting'] = result['pending'].to_i - result['cloning'].to_i
          result['booting'] = 0 if result['booting'] < 0
          result['total'] = result['pending'].to_i + result['ready'].to_i + result['running'].to_i + result['completed'].to_i

          content_type :json
          JSON.pretty_generate(result)
        end

        get '/dashboard/stats/vmpooler/pool/?' do
          result = Hash.new

          $config[:pools].each do |pool|
            result[pool['name']] ||= Hash.new
            result[pool['name']]['size'] = pool['size']
            result[pool['name']]['ready'] = $redis.scard( 'vmpooler__ready__' + pool['name'] )
          end

          if ( params[:history] )
            if ( $config[:graphite]['server'] )
              history ||= Hash.new

              begin
                buffer = open(
                  'http://'+$config[:graphite]['server']+'/render?target='+$config[:graphite]['prefix']+'.ready.*&from=-1hour&format=json'
                ).read
                history = JSON.parse( buffer )

                history.each do |pool|
                  if pool['target'] =~ /.*\.(.*)$/
                    pool['name'] = $1

                    if ( result[pool['name']] )
                      pool['last'] = result[pool['name']]['size']
                      result[pool['name']]['history'] ||= Array.new

                      pool['datapoints'].each do |metric|
                        8.times do |n|
                          if ( metric[0] )
                            pool['last'] = metric[0].to_i
                            result[pool['name']]['history'].push( metric[0].to_i )
                          else
                            result[pool['name']]['history'].push( pool['last'] )
                          end
                        end
                      end
                    end
                  end
                end
              rescue
              end
            else
              $config[:pools].each do |pool|
                result[pool['name']] ||= Hash.new
                result[pool['name']]['history'] = [ $redis.scard( 'vmpooler__ready__' + pool['name'] ) ]
              end
            end
          end

          content_type :json
          JSON.pretty_generate(result)
        end

        get '/dashboard/stats/vmpooler/running/?' do
          result = Hash.new

          $config[:pools].each do |pool|
            running = $redis.scard( 'vmpooler__running__' + pool['name'] )
            pool['major'] = $1 if pool['name'] =~ /^(\w+)\-/

            result[pool['major']] ||= Hash.new

            result[pool['major']]['running'] = result[pool['major']]['running'].to_i + running.to_i
          end

          if ( params[:history] )
            if ( $config[:graphite]['server'] )
              begin
                buffer = open(
                  'http://'+$config[:graphite]['server']+'/render?target='+$config[:graphite]['prefix']+'.running.*&from=-1hour&format=json'
                ).read
                JSON.parse( buffer ).each do |pool|
                  if pool['target'] =~ /.*\.(.*)$/
                    pool['name'] = $1

                    pool['major'] = $1 if pool['name'] =~ /^(\w+)\-/

                    result[pool['major']]['history'] ||= Array.new

                    for i in 0..pool['datapoints'].length
                      if (
                        pool['datapoints'][i] and
                        pool['datapoints'][i][0]
                      )
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

          content_type :json
          JSON.pretty_generate(result)
        end

        get '/status/?' do
          content_type :json

          result = {}

          result['capacity_current'] = 0
          result['capacity_total'] = 0

          result['status'] = 1

          $config[:pools].each do |pool|
            pool['capacity_current'] = $redis.scard( 'vmpooler__ready__' + pool['name'] ).to_i 

            result['capacity_current'] += pool['capacity_current']
            result['capacity_total'] += pool['size'].to_i

            if ( pool['capacity_current'] == 0 )
              result['empty'] ||= []
              result['empty'].push( pool['name'] )
            end
          end

          if ( result['empty'] )
            result['status'] = 0
          end

          result['capacity_perecent'] = ( result['capacity_current'].to_f / result['capacity_total'].to_f ) * 100.0

          result['clone_total'] = $redis.hlen('vmpooler__clone__'+Date.today.to_s)
          if ( result['clone_total'] > 0 )
            result['clone_average'] = $redis.hvals('vmpooler__clone__'+Date.today.to_s).map( &:to_f ).reduce( :+ ) / result['clone_total']
          end

          result['uptime'] = Time.now - $config[:uptime]

          JSON.pretty_generate(Hash[result.sort_by{|k,v| k}])
        end

        get '/vm/?' do
          content_type :json

          result = []

          $config[:pools].each do |pool|
            result.push(pool['name'])
          end

          JSON.pretty_generate(result)
        end

        post '/vm/?' do
          content_type :json

          result = {}

          available = 1

          jdata = JSON.parse(request.body.read)

          jdata.each do |key, val|
            if ( $redis.scard('vmpooler__ready__'+key) < val.to_i )
              available = 0
            end
          end

          if ( available == 1 )
            result['ok'] = true

            jdata.each do |key, val|
              result[key] ||= {}

              result[key]['ok'] = true ##

              val.to_i.times do |i|
                vm = $redis.spop('vmpooler__ready__'+key)

                unless (vm.nil?)
                  $redis.sadd('vmpooler__running__'+key, vm)
                  $redis.hset('vmpooler__active__'+key, vm, Time.now)

                  result[key] ||= {}

                  result[key]['ok'] = true ##

                  if ( result[key]['hostname'] )
                    result[key]['hostname'] = [result[key]['hostname']] if ! result[key]['hostname'].is_a?(Array)
                    result[key]['hostname'].push(vm)
                  else
                    result[key]['hostname'] = vm
                  end
                else
                  result[key]['ok'] = false ##

                  result['ok'] = false
                end
              end
            end
          else
            result['ok'] = false
          end

          if ( result['ok'] and $config[:config]['domain'] )
            result['domain'] = $config[:config]['domain']
          end

          JSON.pretty_generate(result)
        end

        post '/vm/:template/?' do
          content_type :json

          result = {}
          request = {}

          params[:template].split('+').each do |template|
            request[template] ||= 0
            request[template] = request[template] + 1
          end

          available = 1

          request.keys.each do |template|
            if ( $redis.scard('vmpooler__ready__'+template) < request[template] )
              available = 0
            end
          end

          if ( available == 1 )
            result['ok'] = true

            params[:template].split('+').each do |template|
              result[template] ||= {}

              result[template]['ok'] = true ##

              vm = $redis.spop('vmpooler__ready__'+template)

              unless (vm.nil?)
                $redis.sadd('vmpooler__running__'+template, vm)
                $redis.hset('vmpooler__active__'+template, vm, Time.now)

                result[template] ||= {}

                if ( result[template]['hostname'] )
                  result[template]['hostname'] = [result[template]['hostname']] if ! result[template]['hostname'].is_a?(Array)
                  result[template]['hostname'].push(vm)
                else
                  result[template]['hostname'] = vm
                end
              else
                result[template]['ok'] = false ##

                result['ok'] = false
              end
            end
          else
            result['ok'] = false
          end

          if ( result['ok'] and $config[:config]['domain'] )
            result['domain'] = $config[:config]['domain']
          end

          JSON.pretty_generate(result)
        end

        get '/vm/:hostname/?' do
          content_type :json

          result = {}

          result['ok'] = false

          params[:hostname] = hostname_shorten(params[:hostname])

          if $redis.exists('vmpooler__vm__'+params[:hostname])
            result['ok'] = true

            result[params[:hostname]] = {}

            result[params[:hostname]]['template'] = $redis.hget('vmpooler__vm__'+params[:hostname], 'template')
            result[params[:hostname]]['lifetime'] = $redis.hget('vmpooler__vm__'+params[:hostname], 'lifetime') || $config[:config]['vm_lifetime']
            result[params[:hostname]]['running'] = ((Time.now - Time.parse($redis.hget('vmpooler__active__'+result[params[:hostname]]['template'], params[:hostname])))/60/60).round(2)

            if ( $config[:config]['domain'] )
              result[params[:hostname]]['domain'] = $config[:config]['domain']
            end
          end

          JSON.pretty_generate(result)
        end

        delete '/vm/:hostname/?' do
          content_type :json

          result = {}

          result['ok'] = false

          params[:hostname] = hostname_shorten(params[:hostname])

          $config[:pools].each do |pool|
            if $redis.sismember('vmpooler__running__'+pool['name'], params[:hostname])
              $redis.srem('vmpooler__running__'+pool['name'], params[:hostname])
              $redis.sadd('vmpooler__completed__'+pool['name'], params[:hostname])
              result['ok'] = true
            end
          end

          JSON.pretty_generate(result)
        end

        put '/vm/:hostname/?' do
          content_type :json

          result = {}

          result['ok'] = false

          params[:hostname] = hostname_shorten(params[:hostname])

          if $redis.exists('vmpooler__vm__'+params[:hostname])
            jdata = JSON.parse(request.body.read)

            jdata.each do |param, arg|
              case param
                when 'lifetime'
                  $redis.hset('vmpooler__vm__'+params[:hostname], param, arg)
                  result['ok'] = true
              end
            end
          end

          JSON.pretty_generate(result)
        end
      }

      my_app.run!
    end
  end
end

