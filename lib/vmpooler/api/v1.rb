module Vmpooler
  class API
  class V1 < Sinatra::Base
    api_version = '1'
    api_prefix  = "/api/v#{api_version}"

    helpers do
      def get_boot_metrics(date_str)
        boot = {
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

        boot[:count][:total] = $redis.hlen('vmpooler__boot__' + date_str).to_i

        if boot[:count][:total] > 0
          boot_times = get_boot_times(date_str)

          boot[:duration][:total] = boot_times.reduce(:+).to_f
          boot[:duration][:average] = (boot[:duration][:total] / boot[:count][:total]).round(1)
          boot[:duration][:min], boot[:duration][:max] = boot_times.minmax
        end

        boot
      end

      def get_boot_times(date_str)
        $redis.hvals('vmpooler__boot__' + date_str).map(&:to_f)
      end

      def get_capacity_metrics()
        capacity = {
          current: 0,
          total: 0,
          percent: 0
        }

        $config[:pools].each do |pool|
          pool['capacity'] = $redis.scard('vmpooler__ready__' + pool['name']).to_i

          capacity[:current] += pool['capacity']
          capacity[:total] += pool['size'].to_i
        end

        if capacity[:total] > 0
          capacity[:percent] = ((capacity[:current].to_f / capacity[:total].to_f) * 100.0).round(1)
        end

        capacity
      end

      def get_clone_metrics(date_str)
        clone = {
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

        clone[:count][:total] = $redis.hlen('vmpooler__clone__' + date_str).to_i

        if clone[:count][:total] > 0
          clone_times = get_clone_times(date_str)

          clone[:duration][:total] = clone_times.reduce(:+).to_f
          clone[:duration][:average] = (clone[:duration][:total] / clone[:count][:total]).round(1)
          clone[:duration][:min], clone[:duration][:max] = clone_times.minmax
        end

        clone
      end

      def get_clone_times(date_str)
        $redis.hvals('vmpooler__clone__' + date_str).map(&:to_f)
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

        $config[:pools].each do |pool|
          queue[:pending] += $redis.scard('vmpooler__pending__' + pool['name']).to_i
          queue[:ready] += $redis.scard('vmpooler__ready__' + pool['name']).to_i
          queue[:running] += $redis.scard('vmpooler__running__' + pool['name']).to_i
          queue[:completed] += $redis.scard('vmpooler__completed__' + pool['name']).to_i
        end

        queue[:cloning] = $redis.get('vmpooler__tasks__clone').to_i
        queue[:booting] = queue[:pending].to_i - queue[:cloning].to_i
        queue[:booting] = 0 if queue[:booting] < 0
        queue[:total] = queue[:pending].to_i + queue[:ready].to_i + queue[:running].to_i + queue[:completed].to_i

        queue
      end

      def hostname_shorten(hostname)
        if $config[:config]['domain'] && hostname =~ /^\w+\.#{$config[:config]['domain']}$/
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
      result[:clone] = get_clone_metrics(Date.today.to_s)
      result[:boot] = get_boot_metrics(Date.today.to_s)

      # Check for empty pools
      $config[:pools].each do |pool|
        if $redis.scard('vmpooler__ready__' + pool['name']).to_i == 0
          result[:status][:empty] ||= []
          result[:status][:empty].push(pool['name'])

          result[:status][:ok] = false
          result[:status][:message] = "Found #{result[:status][:empty].length} empty pools."
        end
      end

      result[:status][:uptime] = (Time.now - $config[:uptime]).round(1) if $config[:uptime]

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
            total: 0
          },
          count: {
            average: 0,
            min: 0,
            max: 0,
            total: 0
          }
        },
        clone: {
          duration: {
            average: 0,
            min: 0,
            max: 0,
            total: 0
          },
          count: {
            average: 0,
            min: 0,
            max: 0,
            total: 0
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
          boot: get_boot_metrics(date.to_s),
          clone: get_clone_metrics(date.to_s)
        }

        result[:daily].push(daily)
      end

      [:boot, :clone].each do |task|
        daily_counts = []
        daily_durations = []

        result[:daily].each do |daily|
          daily_counts.push(daily[task][:count][:total])

          if daily[task][:count][:total] > 0
            daily_durations.push(daily[task][:duration][:min])
            daily_durations.push(daily[task][:duration][:max])
          end

          result[task][:count][:total] += daily[task][:count][:total]
          result[task][:duration][:total] += daily[task][:duration][:total]

          if result[task][:count][:total] > 0
            result[task][:duration][:average] = result[task][:duration][:total] / result[task][:count][:total]
          end
        end

        result[task][:count][:min], result[task][:count][:max] = daily_counts.minmax
        result[task][:count][:average] = mean(daily_counts)
        result[task][:duration][:min], result[task][:duration][:max] = daily_durations.minmax
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/?" do
      content_type :json

      result = []

      $config[:pools].each do |pool|
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
        if $redis.scard('vmpooler__ready__' + key) < val.to_i
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        jdata.each do |key, val|
          result[key] ||= {}

          result[key]['ok'] = true ##

          val.to_i.times do |_i|
            vm = $redis.spop('vmpooler__ready__' + key)

            unless vm.nil?
              $redis.sadd('vmpooler__running__' + key, vm)
              $redis.hset('vmpooler__active__' + key, vm, Time.now)

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

      if result['ok'] && $config[:config]['domain']
        result['domain'] = $config[:config]['domain']
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
        if $redis.scard('vmpooler__ready__' + template) < request[template]
          available = 0
        end
      end

      if (available == 1)
        result['ok'] = true

        params[:template].split('+').each do |template|
          result[template] ||= {}

          result[template]['ok'] = true ##

          vm = $redis.spop('vmpooler__ready__' + template)

          unless vm.nil?
            $redis.sadd('vmpooler__running__' + template, vm)
            $redis.hset('vmpooler__active__' + template, vm, Time.now)

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

      if result['ok'] && $config[:config]['domain']
        result['domain'] = $config[:config]['domain']
      end

      JSON.pretty_generate(result)
    end

    get "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname])

      if $redis.exists('vmpooler__vm__' + params[:hostname])
        status 200
        result['ok'] = true

        result[params[:hostname]] = {}

        result[params[:hostname]]['template'] = $redis.hget('vmpooler__vm__' + params[:hostname], 'template')
        result[params[:hostname]]['lifetime'] = $redis.hget('vmpooler__vm__' + params[:hostname], 'lifetime') || $config[:config]['vm_lifetime']
        result[params[:hostname]]['running'] = ((Time.now - Time.parse($redis.hget('vmpooler__active__' + result[params[:hostname]]['template'], params[:hostname]))) / 60 / 60).round(2)

        if $config[:config]['domain']
          result[params[:hostname]]['domain'] = $config[:config]['domain']
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

      $config[:pools].each do |pool|
        if $redis.sismember('vmpooler__running__' + pool['name'], params[:hostname])
          $redis.srem('vmpooler__running__' + pool['name'], params[:hostname])
          $redis.sadd('vmpooler__completed__' + pool['name'], params[:hostname])

          status 200
          result['ok'] = true
        end
      end

      JSON.pretty_generate(result)
    end

    put "#{api_prefix}/vm/:hostname/?" do
      content_type :json

      result = {}

      status 404
      result['ok'] = false

      params[:hostname] = hostname_shorten(params[:hostname])

      if $redis.exists('vmpooler__vm__' + params[:hostname])
        jdata = JSON.parse(request.body.read)

        jdata.each do |param, arg|
          case param
            when 'lifetime'
              arg = arg.to_i

              if arg > 0
                $redis.hset('vmpooler__vm__' + params[:hostname], param, arg)

                status 200
                result['ok'] = true
              end
          end
        end
      end

      JSON.pretty_generate(result)
    end
  end
  end
end
