module Vmpooler
  class API
  class V1 < Sinatra::Base
    api_version = '1'
    api_prefix  = "/api/v#{api_version}"

    helpers do
      include Vmpooler::API::Helpers
    end

    def backend
      Vmpooler::API.settings.redis
    end

    def config
      Vmpooler::API.settings.config[:config]
    end

    def pools
      Vmpooler::API.settings.config[:pools]
    end

    def has_valid_token?
      valid_token?(backend)
    end

    def need_auth!
      validate_auth(backend)
    end

    def need_token!
      validate_token(backend)
    end

    get "#{api_prefix}/status/?" do
      content_type :json

      result = {
        status: {
          ok: true,
          message: 'Battle station fully armed and operational.'
        }
      }

      result[:capacity] = get_capacity_metrics(pools, backend)
      result[:queue] = get_queue_metrics(pools, backend)
      result[:clone] = get_task_metrics(backend, 'clone', Date.today.to_s)
      result[:boot] = get_task_metrics(backend, 'boot', Date.today.to_s)

      # Check for empty pools
      pools.each do |pool|
        if backend.scard('vmpooler__ready__' + pool['name']).to_i == 0
          result[:status][:empty] ||= []
          result[:status][:empty].push(pool['name'])

          result[:status][:ok] = false
          result[:status][:message] = "Found #{result[:status][:empty].length} empty pools."
        end
      end

      result[:status][:uptime] = (Time.now - Vmpooler::API.settings.config[:uptime]).round(1) if Vmpooler::API.settings.config[:uptime]

      JSON.pretty_generate(Hash[result.sort_by { |k, _v| k }])
    end

    get "#{api_prefix}/summary/?" do
      content_type :json

      result = {
        boot: {
          duration: {
            average: 0,
            min: 0,
            max: 0,
            total: 0,
            pool: {}
          },
          count: {
            average: 0,
            min: 0,
            max: 0,
            total: 0,
            pool: {}
          }
        },
        clone: {
          duration: {
            average: 0,
            min: 0,
            max: 0,
            total: 0,
            pool: {}
          },
          count: {
            average: 0,
            min: 0,
            max: 0,
            total: 0,
            pool: {}
          }
        },
        tag: {},
        daily: []
      }

      from_param = params[:from] || Date.today.to_s
      to_param   = params[:to]   || Date.today.to_s

      # Validate date formats
      [from_param, to_param].each do |param|
        if !validate_date_str(param.to_s)
          halt 400, "Invalid date format '#{param}', must match YYYY-MM-DD."
        end
      end

      from_date, to_date = Date.parse(from_param), Date.parse(to_param)

      if to_date < from_date
        halt 400, 'Date range is invalid, \'to\' cannot come before \'from\'.'
      elsif from_date > Date.today
        halt 400, 'Date range is invalid, \'from\' must be in the past.'
      end

      (from_date..to_date).each do |date|
        daily = {
          date: date.to_s,
          boot: get_task_metrics(backend, 'boot', date.to_s, :bypool => true),
          clone: get_task_metrics(backend, 'clone', date.to_s, :bypool => true),
          tag: get_tag_metrics(backend, date.to_s)
        }

        result[:daily].push(daily)
      end

      [:boot, :clone].each do |task|
        daily_counts = []
        daily_counts_bypool = {}
        daily_durations = []
        daily_durations_bypool = {}

        result[:daily].each do |daily|
          if daily[task][:count][:pool]
            daily[task][:count][:pool].each_key do |pool|
              daily_counts_bypool[pool] ||= []
              daily_counts_bypool[pool].push(daily[task][:count][:pool][pool][:total])

              if daily[task][:count][:pool][pool][:total] > 0
                daily_durations_bypool[pool] ||= []
                daily_durations_bypool[pool].push(daily[task][:duration][:pool][pool][:min])
                daily_durations_bypool[pool].push(daily[task][:duration][:pool][pool][:max])
              end

              result[task][:count][:pool][pool] ||= {}
              result[task][:count][:pool][pool][:total] ||= 0
              result[task][:count][:pool][pool][:total] += daily[task][:count][:pool][pool][:total]

              result[task][:duration][:pool][pool] ||= {}
              result[task][:duration][:pool][pool][:total] ||= 0
              result[task][:duration][:pool][pool][:total] += daily[task][:duration][:pool][pool][:total]
            end
          end

          daily_counts.push(daily[task][:count][:total])
          if daily[task][:count][:total] > 0
            daily_durations.push(daily[task][:duration][:min])
            daily_durations.push(daily[task][:duration][:max])
          end

          result[task][:count][:total] += daily[task][:count][:total]
          result[task][:duration][:total] += daily[task][:duration][:total]
        end

        if result[task][:count][:total] > 0
          result[task][:duration][:average] = result[task][:duration][:total] / result[task][:count][:total] ##??
        end

        result[task][:count][:min], result[task][:count][:max] = daily_counts.minmax
        result[task][:count][:average] = mean(daily_counts)

        if daily_durations.length > 0
          result[task][:duration][:min], result[task][:duration][:max] = daily_durations.minmax
        end

        daily_counts_bypool.each_key do |pool|
          result[task][:count][:pool][pool][:min], result[task][:count][:pool][pool][:max] = daily_counts_bypool[pool].minmax
          result[task][:count][:pool][pool][:average] = mean(daily_counts_bypool[pool])

          if daily_durations_bypool[pool].length > 0
            result[task][:duration][:pool][pool] ||= {}
            result[task][:duration][:pool][pool][:min], result[task][:duration][:pool][pool][:max] = daily_durations_bypool[pool].minmax
          end

          if result[task][:count][:pool][pool][:total] > 0
           result[task][:duration][:pool][pool][:average] = result[task][:duration][:pool][pool][:total] / result[task][:count][:pool][pool][:total]
          end
        end
      end

      result[:daily].each do |daily|
        daily[:tag].each_key do |tag|
          result[:tag][tag] ||= {}

          daily[:tag][tag].each do |key, value|
            result[:tag][tag][key] ||= 0
            result[:tag][tag][key] += value
          end
        end
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/token/:token/?" do
      content_type :json

      status 404
      result = { 'ok' => false }

      if Vmpooler::API.settings.config[:auth]
        status 401

        need_auth!

        token = backend.hgetall('vmpooler__token__' + params[:token])

        if not token.nil? and not token.empty?
          status 200
          result = { 'ok' => true, params[:token] => token }
        else
          status 404
        end
      end

      JSON.pretty_generate(result)
    end

    delete "#{api_prefix}/token/:token/?" do
      content_type :json

      status 404
      result = { 'ok' => false }

      if Vmpooler::API.settings.config[:auth]
        status 401

        need_auth!

        if backend.del('vmpooler__token__' + params[:token]).to_i > 0
          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end

    post "#{api_prefix}/token" do
      content_type :json

      status 404
      result = { 'ok' => false }

      if Vmpooler::API.settings.config[:auth]
        status 401

        need_auth!

        o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
        result['token'] = o[rand(25)] + (0...31).map { o[rand(o.length)] }.join

        backend.hset('vmpooler__token__' + result['token'], 'user', @auth.username)
        backend.hset('vmpooler__token__' + result['token'], 'timestamp', Time.now)

        status 200
        result['ok'] = true
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/?" do
      content_type :json

      result = []

      pools.each do |pool|
        result.push(pool['name'])
      end

      JSON.pretty_generate(result)
    end

    post "#{api_prefix}/vm/?" do
      content_type :json

      result = {}

      available = 1

      jdata = JSON.parse(request.body.read)

      jdata.each do |key, val|
        if backend.scard('vmpooler__ready__' + key).to_i < val.to_i
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        jdata.each do |key, val|
          result[key] ||= {}

          result[key]['ok'] = true ##

          val.to_i.times do |_i|
            vm = backend.spop('vmpooler__ready__' + key)

            unless vm.nil?
              backend.sadd('vmpooler__running__' + key, vm)
              backend.hset('vmpooler__active__' + key, vm, Time.now)
              backend.hset('vmpooler__vm__' + vm, 'checkout', Time.now)

              if Vmpooler::API.settings.config[:auth] and has_valid_token?
                backend.hset('vmpooler__vm__' + vm, 'token:token', request.env['HTTP_X_AUTH_TOKEN'])
                backend.hset('vmpooler__vm__' + vm, 'token:user',
                  backend.hget('vmpooler__token__' + request.env['HTTP_X_AUTH_TOKEN'], 'user')
                )

                if config['vm_lifetime_auth'].to_i > 0
                  backend.hset('vmpooler__vm__' + vm, 'lifetime', config['vm_lifetime_auth'].to_i)
                end
              end

              result[key] ||= {}

              result[key]['ok'] = true ##

              if result[key]['hostname']
                result[key]['hostname'] = [result[key]['hostname']] unless result[key]['hostname'].is_a?(Array)
                result[key]['hostname'].push(vm)
              else
                result[key]['hostname'] = vm
              end
            else
              result[key]['ok'] = false ##

              status 503
              result['ok'] = false
            end
          end
        end
      else
        status 503
        result['ok'] = false
      end

      if result['ok'] && config['domain']
        result['domain'] = config['domain']
      end

      JSON.pretty_generate(result)
    end

    post "#{api_prefix}/vm/:template/?" do
      content_type :json

      result = {}
      request = {}

      params[:template].split('+').each do |template|
        request[template] ||= 0
        request[template] = request[template] + 1
      end

      available = 1

      request.keys.each do |template|
        if backend.scard('vmpooler__ready__' + template) < request[template]
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        params[:template].split('+').each do |template|
          result[template] ||= {}

          result[template]['ok'] = true ##

          vm = backend.spop('vmpooler__ready__' + template)

          unless vm.nil?
            backend.sadd('vmpooler__running__' + template, vm)
            backend.hset('vmpooler__active__' + template, vm, Time.now)
            backend.hset('vmpooler__vm__' + vm, 'checkout', Time.now)

            result[template] ||= {}

            if result[template]['hostname']
              result[template]['hostname'] = [result[template]['hostname']] unless result[template]['hostname'].is_a?(Array)
              result[template]['hostname'].push(vm)
            else
              result[template]['hostname'] = vm
            end
          else
            result[template]['ok'] = false ##

            status 503
            result['ok'] = false
          end
        end
      else
        status 503
        result['ok'] = false
      end

      if result['ok'] && config['domain']
        result['domain'] = config['domain']
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if backend.exists('vmpooler__vm__' + params[:hostname])
        status 200
        result['ok'] = true

        rdata = backend.hgetall('vmpooler__vm__' + params[:hostname])

        result[params[:hostname]] = {}

        result[params[:hostname]]['template'] = rdata['template']
        result[params[:hostname]]['lifetime'] = (rdata['lifetime'] || config['vm_lifetime']).to_i

        if rdata['destroy']
          result[params[:hostname]]['running'] = ((Time.parse(rdata['destroy']) - Time.parse(rdata['checkout'])) / 60 / 60).round(2)
          result[params[:hostname]]['state'] = 'destroyed'
        elsif rdata['checkout']
          result[params[:hostname]]['running'] = ((Time.now - Time.parse(rdata['checkout'])) / 60 / 60).round(2)
          result[params[:hostname]]['state'] = 'running'
        elsif rdata['check']
          result[params[:hostname]]['state'] = 'ready'
        else
          result[params[:hostname]]['state'] = 'pending'
        end

        rdata.keys.each do |key|
          if key.match('^tag\:(.+?)$')
            result[params[:hostname]]['tags'] ||= {}
            result[params[:hostname]]['tags'][$1] = rdata[key]
          end
        end

        if config['domain']
          result[params[:hostname]]['domain'] = config['domain']
        end
      end

      JSON.pretty_generate(result)
    end

    delete "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      pools.each do |pool|
        if backend.sismember('vmpooler__running__' + pool['name'], params[:hostname])
          backend.srem('vmpooler__running__' + pool['name'], params[:hostname])
          backend.sadd('vmpooler__completed__' + pool['name'], params[:hostname])

          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end

    put "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      status 404
      result = { 'ok' => false }

      failure = false

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if backend.exists('vmpooler__vm__' + params[:hostname])
        begin
          jdata = JSON.parse(request.body.read)
        rescue
          halt 400, JSON.pretty_generate(result)
        end

        # Validate data payload
        jdata.each do |param, arg|
          case param
            when 'lifetime'
              need_token! if Vmpooler::API.settings.config[:auth]

              unless arg.to_i > 0
                failure = true
              end
            when 'tags'
              unless arg.is_a?(Hash)
                failure = true
              end
            else
              failure = true
          end
        end

        if failure
          status 400
        else
          jdata.each do |param, arg|
            case param
              when 'lifetime'
                need_token! if Vmpooler::API.settings.config[:auth]

                arg = arg.to_i

                backend.hset('vmpooler__vm__' + params[:hostname], param, arg)
              when 'tags'
                arg.keys.each do |tag|
                  if Vmpooler::API.settings.config[:tagfilter] and Vmpooler::API.settings.config[:tagfilter][tag]
                    filter = Vmpooler::API.settings.config[:tagfilter][tag]
                    arg[tag] = arg[tag].match(filter).captures.join if arg[tag].match(filter)
                  end

                  backend.hset('vmpooler__vm__' + params[:hostname], 'tag:' + tag, arg[tag])
                  backend.hset('vmpooler__tag__' + Date.today.to_s, params[:hostname] + ':' + tag, arg[tag])
                end
            end
          end

          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end
  end
  end
end
