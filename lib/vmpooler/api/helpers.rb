module Vmpooler

  class API

    module Helpers

      def has_token?
        request.env['HTTP_X_AUTH_TOKEN'].nil? ? false : true
      end

      def valid_token?(backend)
        return false unless has_token?

        backend.exists('vmpooler__token__' + request.env['HTTP_X_AUTH_TOKEN']) ? true : false
      end

      def validate_token(backend)
        if valid_token?(backend)
          backend.hset('vmpooler__token__' + request.env['HTTP_X_AUTH_TOKEN'], 'last', Time.now)

          return true
        end

        content_type :json

        result = { 'ok' => false }

        headers['WWW-Authenticate'] = 'Basic realm="Authentication required"'
        halt 401, JSON.pretty_generate(result)
      end

      def validate_auth(backend)
        return if authorized?

        content_type :json

        result = { 'ok' => false }

        headers['WWW-Authenticate'] = 'Basic realm="Authentication required"'
        halt 401, JSON.pretty_generate(result)
      end

      def authorized?
        @auth ||= Rack::Auth::Basic::Request.new(request.env)

        if @auth.provided? and @auth.basic? and @auth.credentials
          username, password = @auth.credentials

          if authenticate(Vmpooler::API.settings.config[:auth], username, password)
            return true
          end
        end

        return false
      end

      def authenticate_ldap(port, host, user_object, base, username_str, password_str)
        ldap = Net::LDAP.new(
          :host => host,
          :port => port,
          :encryption => {
            :method => :start_tls,
            :tls_options => { :ssl_version => 'TLSv1' }
          },
          :base => base,
          :auth => {
            :method => :simple,
            :username => "#{user_object}=#{username_str},#{base}",
            :password => password_str
          }
        )

        return true if ldap.bind

        return false
      end

      def authenticate(auth, username_str, password_str)
        case auth['provider']
          when 'dummy'
            return (username_str != password_str)
          when 'ldap'
            ldap_base = auth[:ldap]['base']
            ldap_port = auth[:ldap]['port'] || 389

            if ldap_base.is_a? Array
              ldap_base.each do |search_base|
                result = authenticate_ldap(
                  ldap_port,
                  auth[:ldap]['host'],
                  auth[:ldap]['user_object'],
                  search_base,
                  username_str,
                  password_str
                )
                return true if result == true
              end
            else
              result = authenticate_ldap(
                ldap_port,
                auth[:ldap]['host'],
                auth[:ldap]['user_object'],
                ldap_base,
                username_str,
                password_str
              )
              return result
            end

            return false
          end
      end

      def export_tags(backend, hostname, tags)
        tags.each_pair do |tag, value|
          next if value.nil? or value.empty?

          backend.hset('vmpooler__vm__' + hostname, 'tag:' + tag, value)
          backend.hset('vmpooler__tag__' + Date.today.to_s, hostname + ':' + tag, value)
        end
      end

      def filter_tags(tags)
        return unless Vmpooler::API.settings.config[:tagfilter]

        tags.each_pair do |tag, value|
          next unless filter = Vmpooler::API.settings.config[:tagfilter][tag]

          tags[tag] = value.match(filter).captures.join if value.match(filter)
        end

        tags
      end

      def mean(list)
        s = list.map(&:to_f).reduce(:+).to_f
        (s > 0 && list.length > 0) ? s / list.length.to_f : 0
      end

      def validate_date_str(date_str)
        /^\d{4}-\d{2}-\d{2}$/ === date_str
      end

      def hostname_shorten(hostname, domain=nil)
        if domain && hostname =~ /^[\w-]+\.#{domain}$/
          hostname = hostname[/[^\.]+/]
        end

        hostname
      end

      def get_task_times(backend, task, date_str)
        backend.hvals("vmpooler__#{task}__" + date_str).map(&:to_f)
      end

      # Takes the pools and a key to run scard on
      # returns an integer for the total count
      def get_total_across_pools_redis_scard(pools, key, backend)
        # using pipelined is much faster than querying each of the pools and adding them
        # as we get the result.
        res = backend.pipelined do
          pools.each do |pool|
            backend.scard(key + pool['name'])
          end
        end
        res.inject(0) { |m, x| m + x }.to_i
      end

      # Takes the pools and a key to run scard on
      # returns a hash with each pool name as key and the value being the count as integer
      def get_list_across_pools_redis_scard(pools, key, backend)
        # using pipelined is much faster than querying each of the pools and adding them
        # as we get the result.
        temp_hash = {}
        res = backend.pipelined do
          pools.each do |pool|
            backend.scard(key + pool['name'])
          end
        end
        pools.each_with_index do |pool, i|
          temp_hash[pool['name']] = res[i].to_i
        end
        temp_hash
      end

      # Takes the pools and a key to run hget on
      # returns a hash with each pool name as key and the value as string
      def get_list_across_pools_redis_hget(pools, key, backend)
        # using pipelined is much faster than querying each of the pools and adding them
        # as we get the result.
        temp_hash = {}
        res = backend.pipelined do
          pools.each do |pool|
            backend.hget(key, pool['name'])
          end
        end
        pools.each_with_index do |pool, i|
          temp_hash[pool['name']] = res[i].to_s
        end
        temp_hash
      end

      def get_capacity_metrics(pools, backend)
        capacity = {
            current: 0,
            total: 0,
            percent: 0
        }

        pools.each do |pool|
          capacity[:total] += pool['size'].to_i
        end

        capacity[:current] = get_total_across_pools_redis_scard(pools, 'vmpooler__ready__', backend)

        if capacity[:total] > 0
          capacity[:percent] = ((capacity[:current].to_f / capacity[:total].to_f) * 100.0).round(1)
        end

        capacity
      end

      def get_queue_metrics(pools, backend)
        queue = {
            pending: 0,
            cloning: 0,
            booting: 0,
            ready: 0,
            running: 0,
            completed: 0,
            total: 0
        }

        queue[:pending]   = get_total_across_pools_redis_scard(pools, 'vmpooler__pending__', backend)
        queue[:ready]     = get_total_across_pools_redis_scard(pools, 'vmpooler__ready__', backend)
        queue[:running]   = get_total_across_pools_redis_scard(pools, 'vmpooler__running__', backend)
        queue[:completed] = get_total_across_pools_redis_scard(pools, 'vmpooler__completed__', backend)

        queue[:cloning] = backend.get('vmpooler__tasks__clone').to_i
        queue[:booting] = queue[:pending].to_i - queue[:cloning].to_i
        queue[:booting] = 0 if queue[:booting] < 0
        queue[:total]   = queue[:pending].to_i + queue[:ready].to_i + queue[:running].to_i + queue[:completed].to_i

        queue
      end

      def get_tag_metrics(backend, date_str, opts = {})
        opts = {:only => false}.merge(opts)

        tags = {}

        backend.hgetall('vmpooler__tag__' + date_str).each do |key, value|
          hostname = 'unknown'
          tag = 'unknown'

          if key =~ /\:/
            hostname, tag = key.split(':', 2)
          end

          if opts[:only]
            next unless tag == opts[:only]
          end

          tags[tag] ||= {}
          tags[tag][value] ||= 0
          tags[tag][value] += 1

          tags[tag]['total'] ||= 0
          tags[tag]['total'] += 1
        end

        tags
      end

      def get_tag_summary(backend, from_date, to_date, opts = {})
        opts = {:only => false}.merge(opts)

        result = {
          tag: {},
          daily: []
        }

        (from_date..to_date).each do |date|
          daily = {
            date: date.to_s,
            tag: get_tag_metrics(backend, date.to_s, opts)
          }
          result[:daily].push(daily)
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

        result
      end

      def get_task_metrics(backend, task_str, date_str, opts = {})
        opts = {:bypool => false, :only => false}.merge(opts)

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

        task[:count][:total] = backend.hlen('vmpooler__' + task_str + '__' + date_str).to_i

        if task[:count][:total] > 0
          if opts[:bypool] == true
            task_times_bypool = {}

            task[:count][:pool]    = {}
            task[:duration][:pool] = {}

            backend.hgetall('vmpooler__' + task_str + '__' + date_str).each do |key, value|
              pool     = 'unknown'
              hostname = 'unknown'

              if key =~ /\:/
                pool, hostname = key.split(':')
              else
                hostname = key
              end

              task[:count][:pool][pool]    ||= {}
              task[:duration][:pool][pool] ||= {}

              task_times_bypool[pool] ||= []
              task_times_bypool[pool].push(value.to_f)
            end

            task_times_bypool.each_key do |pool|
              task[:count][:pool][pool][:total] = task_times_bypool[pool].length

              task[:duration][:pool][pool][:total]                                   = task_times_bypool[pool].reduce(:+).to_f
              task[:duration][:pool][pool][:average]                                 = (task[:duration][:pool][pool][:total] / task[:count][:pool][pool][:total]).round(1)
              task[:duration][:pool][pool][:min], task[:duration][:pool][pool][:max] = task_times_bypool[pool].minmax
            end
          end

          task_times = get_task_times(backend, task_str, date_str)

          task[:duration][:total]                      = task_times.reduce(:+).to_f
          task[:duration][:average]                    = (task[:duration][:total] / task[:count][:total]).round(1)
          task[:duration][:min], task[:duration][:max] = task_times.minmax
        end

        if opts[:only]
          task.each_key do |key|
            task.delete(key) unless key.to_s == opts[:only]
          end
        end

        task
      end

      def get_task_summary(backend, task_str, from_date, to_date, opts = {})
        opts = {:bypool => false, :only => false}.merge(opts)

        task_sym = task_str.to_sym

        result = {
          task_sym => {},
          daily: []
        }

        (from_date..to_date).each do |date|
          daily = {
            date: date.to_s,
            task_sym => get_task_metrics(backend, task_str, date.to_s, opts)
          }
          result[:daily].push(daily)
        end

        daily_task = {}
        daily_task_bypool = {} if opts[:bypool] == true

        result[:daily].each do |daily|
          daily[task_sym].each_key do |type|
            result[task_sym][type] ||= {}
            daily_task[type] ||= {}

            ['min', 'max'].each do |key|
              if daily[task_sym][type][key]
                daily_task[type][:data] ||= []
                daily_task[type][:data].push(daily[task_sym][type][key])
              end
            end

            result[task_sym][type][:total] ||= 0
            result[task_sym][type][:total] += daily[task_sym][type][:total]

            if opts[:bypool] == true
              result[task_sym][type][:pool] ||= {}
              daily_task_bypool[type] ||= {}

              next unless daily[task_sym][type][:pool]

              daily[task_sym][type][:pool].each_key do |pool|
                result[task_sym][type][:pool][pool] ||= {}
                daily_task_bypool[type][pool] ||= {}

                ['min', 'max'].each do |key|
                  if daily[task_sym][type][:pool][pool][key.to_sym]
                    daily_task_bypool[type][pool][:data] ||= []
                    daily_task_bypool[type][pool][:data].push(daily[task_sym][type][:pool][pool][key.to_sym])
                  end
                end

                result[task_sym][type][:pool][pool][:total] ||= 0
                result[task_sym][type][:pool][pool][:total] += daily[task_sym][type][:pool][pool][:total]
              end
            end
          end
        end

        result[task_sym].each_key do |type|
          if daily_task[type][:data]
            result[task_sym][type][:min], result[task_sym][type][:max] = daily_task[type][:data].minmax
            result[task_sym][type][:average] = mean(daily_task[type][:data])
          end

          if opts[:bypool] == true
            result[task_sym].each_key do |type|
              result[task_sym][type][:pool].each_key do |pool|
                if daily_task_bypool[type][pool][:data]
                  result[task_sym][type][:pool][pool][:min], result[task_sym][type][:pool][pool][:max] = daily_task_bypool[type][pool][:data].minmax
                  result[task_sym][type][:pool][pool][:average] = mean(daily_task_bypool[type][pool][:data])
                end
              end
            end
          end
        end

        result
      end

      def pool_index(pools)
        pools_hash = {}
        index = 0
        pools.each do |pool|
          pools_hash[pool['name']] = index
          index += 1
        end
        pools_hash
      end

      def template_ready?(pool, backend)
        prepared_template = backend.hget('vmpooler__template__prepared', pool['name'])
        return false if prepared_template.nil?
        return true if pool['template'] == prepared_template

        return false
      end

      def is_integer?(x)
        Integer(x)
        true
      rescue StandardError
        false
      end

      def open_socket(host, domain = nil, timeout = 1, port = 22, &_block)
        Timeout.timeout(timeout) do
          target_host = host
          target_host = "#{host}.#{domain}" if domain
          sock = TCPSocket.new target_host, port
          begin
            yield sock if block_given?
          ensure
            sock.close
          end
        end
      end

      def vm_ready?(vm_name, domain = nil)
        begin
          open_socket(vm_name, domain)
        rescue StandardError => _e
          return false
        end

        true
      end
    end
  end
end
