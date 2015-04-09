module Vmpooler
  class API
  class V1 < Sinatra::Base
    api_version = '1'
    api_prefix  = "/api/v#{api_version}"

    helpers do
      def get_capacity_metrics()
        capacity = {
          current: 0,
          total: 0,
          percent: 0
        }

        Vmpooler::API.settings.config[:pools].each do |pool|
          pool['capacity'] = Vmpooler::API.settings.redis.scard('vmpooler__ready__' + pool['name']).to_i

          capacity[:current] += pool['capacity']
          capacity[:total] += pool['size'].to_i
        end

        if capacity[:total] > 0
          capacity[:percent] = ((capacity[:current].to_f / capacity[:total].to_f) * 100.0).round(1)
        end

        capacity
      end

      def get_queue_metrics()
        queue = {
          pending: 0,
          cloning: 0,
          booting: 0,
          ready: 0,
          running: 0,
          completed: 0,
          total: 0
        }

        Vmpooler::API.settings.config[:pools].each do |pool|
          queue[:pending] += Vmpooler::API.settings.redis.scard('vmpooler__pending__' + pool['name']).to_i
          queue[:ready] += Vmpooler::API.settings.redis.scard('vmpooler__ready__' + pool['name']).to_i
          queue[:running] += Vmpooler::API.settings.redis.scard('vmpooler__running__' + pool['name']).to_i
          queue[:completed] += Vmpooler::API.settings.redis.scard('vmpooler__completed__' + pool['name']).to_i
        end

        queue[:cloning] = Vmpooler::API.settings.redis.get('vmpooler__tasks__clone').to_i
        queue[:booting] = queue[:pending].to_i - queue[:cloning].to_i
        queue[:booting] = 0 if queue[:booting] < 0
        queue[:total] = queue[:pending].to_i + queue[:ready].to_i + queue[:running].to_i + queue[:completed].to_i

        queue
      end

      def get_task_metrics(task_str, date_str, opts = {})
        opts = { :bypool => false }.merge(opts)

        task = {
          duration: {
            average: 0,
            min: 0,
            max: 0,
            total: 0
          },
          count: {
            total: 0
          }
        }

        task[:count][:total] = Vmpooler::API.settings.redis.hlen('vmpooler__' + task_str + '__' + date_str).to_i

        if task[:count][:total] > 0
          if opts[:bypool] == true
            task_times_bypool = {}

            task[:count][:pool] = {}
            task[:duration][:pool] = {}

            Vmpooler::API.settings.redis.hgetall('vmpooler__' + task_str + '__' + date_str).each do |key, value|
              pool = 'unknown'
              hostname = 'unknown'

              if key =~ /\:/
                pool, hostname = key.split(':')
              else
                hostname = key
              end

              task[:count][:pool][pool] ||= {}
              task[:duration][:pool][pool] ||= {}

              task_times_bypool[pool] ||= []
              task_times_bypool[pool].push(value.to_f)
            end

            task_times_bypool.each_key do |pool|
              task[:count][:pool][pool][:total] = task_times_bypool[pool].length

              task[:duration][:pool][pool][:total] = task_times_bypool[pool].reduce(:+).to_f
              task[:duration][:pool][pool][:average] = (task[:duration][:pool][pool][:total] / task[:count][:pool][pool][:total]).round(1)
              task[:duration][:pool][pool][:min], task[:duration][:pool][pool][:max] = task_times_bypool[pool].minmax
            end
          end

          task_times = get_task_times(task_str, date_str)

          task[:duration][:total] = task_times.reduce(:+).to_f
          task[:duration][:average] = (task[:duration][:total] / task[:count][:total]).round(1)
          task[:duration][:min], task[:duration][:max] = task_times.minmax
        end

        task
      end

      def get_task_times(task, date_str)
        Vmpooler::API.settings.redis.hvals("vmpooler__#{task}__" + date_str).map(&:to_f)
      end

      def hostname_shorten(hostname)
        if Vmpooler::API.settings.config[:config]['domain'] && hostname =~ /^\w+\.#{Vmpooler::API.settings.config[:config]['domain']}$/
          hostname = hostname[/[^\.]+/]
        end

        hostname
      end

      def mean(list)
        s = list.map(&:to_f).reduce(:+).to_f
        (s > 0 && list.length > 0) ? s / list.length.to_f : 0
      end

      def validate_date_str(date_str)
        /^\d{4}-\d{2}-\d{2}$/ === date_str
      end
    end

    get "#{api_prefix}/status/?" do
      content_type :json

      result = {
        status: {
          ok: true,
          message: 'Battle station fully armed and operational.'
        }
      }

      result[:capacity] = get_capacity_metrics()
      result[:queue] = get_queue_metrics()
      result[:clone] = get_task_metrics('clone', Date.today.to_s)
      result[:boot] = get_task_metrics('boot', Date.today.to_s)

      # Check for empty pools
      Vmpooler::API.settings.config[:pools].each do |pool|
        if Vmpooler::API.settings.redis.scard('vmpooler__ready__' + pool['name']).to_i == 0
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
          boot: get_task_metrics('boot', date.to_s, :bypool => true),
          clone: get_task_metrics('clone', date.to_s, :bypool => true)
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

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/?" do
      content_type :json

      result = []

      Vmpooler::API.settings.config[:pools].each do |pool|
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
        if Vmpooler::API.settings.redis.scard('vmpooler__ready__' + key) < val.to_i
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        jdata.each do |key, val|
          result[key] ||= {}

          result[key]['ok'] = true ##

          val.to_i.times do |_i|
            vm = Vmpooler::API.settings.redis.spop('vmpooler__ready__' + key)

            unless vm.nil?
              Vmpooler::API.settings.redis.sadd('vmpooler__running__' + key, vm)
              Vmpooler::API.settings.redis.hset('vmpooler__active__' + key, vm, Time.now)
              Vmpooler::API.settings.redis.hset('vmpooler__vm__' + vm, 'checkout', Time.now)

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

      if result['ok'] && Vmpooler::API.settings.config[:config]['domain']
        result['domain'] = Vmpooler::API.settings.config[:config]['domain']
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
        if Vmpooler::API.settings.redis.scard('vmpooler__ready__' + template) < request[template]
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        params[:template].split('+').each do |template|
          result[template] ||= {}

          result[template]['ok'] = true ##

          vm = Vmpooler::API.settings.redis.spop('vmpooler__ready__' + template)

          unless vm.nil?
            Vmpooler::API.settings.redis.sadd('vmpooler__running__' + template, vm)
            Vmpooler::API.settings.redis.hset('vmpooler__active__' + template, vm, Time.now)
            Vmpooler::API.settings.redis.hset('vmpooler__vm__' + vm, 'checkout', Time.now)

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

      if result['ok'] && Vmpooler::API.settings.config[:config]['domain']
        result['domain'] = Vmpooler::API.settings.config[:config]['domain']
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname])

      if Vmpooler::API.settings.redis.exists('vmpooler__vm__' + params[:hostname])
        status 200
        result['ok'] = true

        rdata = Vmpooler::API.settings.redis.hgetall('vmpooler__vm__' + params[:hostname])

        result[params[:hostname]] = {}

        result[params[:hostname]]['template'] = rdata['template']
        result[params[:hostname]]['lifetime'] = (rdata['lifetime'] || Vmpooler::API.settings.config[:config]['vm_lifetime']).to_i

        if rdata['destroy']
          result[params[:hostname]]['running'] = ((Time.parse(rdata['destroy']) - Time.parse(rdata['checkout'])) / 60 / 60).round(2)
        else
          result[params[:hostname]]['running'] = ((Time.now - Time.parse(rdata['checkout'])) / 60 / 60).round(2)
        end

        rdata.keys.each do |key|
          if key.match('^tag\:(.+?)$')
            result[params[:hostname]]['tags'] ||= {}
            result[params[:hostname]]['tags'][$1] = rdata[key]
          end
        end

        if Vmpooler::API.settings.config[:config]['domain']
          result[params[:hostname]]['domain'] = Vmpooler::API.settings.config[:config]['domain']
        end
      end

      JSON.pretty_generate(result)
    end

    delete "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname])

      Vmpooler::API.settings.config[:pools].each do |pool|
        if Vmpooler::API.settings.redis.sismember('vmpooler__running__' + pool['name'], params[:hostname])
          Vmpooler::API.settings.redis.srem('vmpooler__running__' + pool['name'], params[:hostname])
          Vmpooler::API.settings.redis.sadd('vmpooler__completed__' + pool['name'], params[:hostname])

          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end

    put "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      failure = false

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname])

      if Vmpooler::API.settings.redis.exists('vmpooler__vm__' + params[:hostname])
        begin
          jdata = JSON.parse(request.body.read)
        rescue
          status 400
          return JSON.pretty_generate(result)
        end

        # Validate data payload
        jdata.each do |param, arg|
          case param
            when 'lifetime'
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
                arg = arg.to_i

                Vmpooler::API.settings.redis.hset('vmpooler__vm__' + params[:hostname], param, arg)
              when 'tags'
                arg.keys.each do |tag|
                    Vmpooler::API.settings.redis.hset('vmpooler__vm__' + params[:hostname], 'tag:' + tag, arg[tag])
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
