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

      boot = get_task_summary(backend, 'boot', from_date, to_date, :bypool => true)
      clone = get_task_summary(backend, 'clone', from_date, to_date, :bypool => true)
      tag = get_tag_summary(backend, from_date, to_date)

      result[:boot] = boot[:boot]
      result[:clone] = clone[:clone]
      result[:tag] = tag[:tag]

      daily = {}

      boot[:daily].each do |day|
        daily[day[:date]] ||= {}
        daily[day[:date]][:boot] = day[:boot]
      end

      clone[:daily].each do |day|
        daily[day[:date]] ||= {}
        daily[day[:date]][:clone] = day[:clone]
      end

      tag[:daily].each do |day|
        daily[day[:date]] ||= {}
        daily[day[:date]][:tag] = day[:tag]
      end

      daily.each_key do |day|
        result[:daily].push({
          date: day,
          boot: daily[day][:boot],
          clone: daily[day][:clone],
          tag: daily[day][:tag]
        })
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/summary/:route/?:key?/?" do
      content_type :json

      result = {}

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

      case params[:route]
        when 'boot'
          result = get_task_summary(backend, 'boot', from_date, to_date, :bypool => true, :only => params[:key])
        when 'clone'
          result = get_task_summary(backend, 'clone', from_date, to_date, :bypool => true, :only => params[:key])
        when 'tag'
          result = get_tag_summary(backend, from_date, to_date, :only => params[:key])
        else
          halt 404, JSON.pretty_generate({ 'ok' => false })
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/token/?" do
      content_type :json

      status 404
      result = { 'ok' => false }

      if Vmpooler::API.settings.config[:auth]
        status 401

        need_auth!

        backend.keys('vmpooler__token__*').each do |key|
          data = backend.hgetall(key)

          if data['user'] == Rack::Auth::Basic::Request.new(request.env).username
            token = key.split('__').last

            result[token] ||= {}
            result[token]['created'] = data['timestamp']

            result['ok'] = true
          end
        end

        if result['ok']
          status 200
        else
          status 404
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

      rdata = backend.hgetall('vmpooler__vm__' + params[:hostname])
      unless rdata.empty?
        status 200
        result['ok'] = true

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

          if key.match('^snapshot\:(.+?)$')
            result[params[:hostname]]['snapshots'] ||= []
            result[params[:hostname]]['snapshots'].push($1)
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

      rdata = backend.hgetall('vmpooler__vm__' + params[:hostname])
      unless rdata.empty?
        need_token! if rdata['token:token']

        if backend.srem('vmpooler__running__' + rdata['template'], params[:hostname])
          backend.sadd('vmpooler__completed__' + rdata['template'], params[:hostname])

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

              if config['allowed_tags']
                failure = true if not (arg.keys - config['allowed_tags']).empty?
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
                filter_tags(arg)
                export_tags(backend, params[:hostname], arg)
            end
          end

          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end

    post "#{api_prefix}/vm/:hostname/snapshot/?" do
      content_type :json

      need_token! if Vmpooler::API.settings.config[:auth]

      status 404
      result = { 'ok' => false }

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if backend.exists('vmpooler__vm__' + params[:hostname])
        result[params[:hostname]] = {}

        o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
        result[params[:hostname]]['snapshot'] = o[rand(25)] + (0...31).map { o[rand(o.length)] }.join

        backend.sadd('vmpooler__tasks__snapshot', params[:hostname] + ':' + result[params[:hostname]]['snapshot'])

        status 202
        result['ok'] = true
      end

      JSON.pretty_generate(result)
    end

    post "#{api_prefix}/vm/:hostname/snapshot/:snapshot/?" do
      content_type :json

      need_token! if Vmpooler::API.settings.config[:auth]

      status 404
      result = { 'ok' => false }

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      unless backend.hget('vmpooler__vm__' + params[:hostname], 'snapshot:' + params[:snapshot]).to_i.zero?
        backend.sadd('vmpooler__tasks__snapshot-revert', params[:hostname] + ':' + params[:snapshot])

        status 202
        result['ok'] = true
      end

      JSON.pretty_generate(result)
    end
  end
  end
end
