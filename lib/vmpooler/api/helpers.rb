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
        return if valid_token?(backend)

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

      def authenticate(auth, username_str, password_str)
        case auth['provider']
          when 'ldap'
            require 'rubygems'
            require 'net/ldap'

            ldap = Net::LDAP.new(
              :host => auth[:ldap]['host'],
              :port => auth[:ldap]['port'] || 389,
              :encryption => {
                :method => :start_tls,
                :tls_options => { :ssl_version => 'TLSv1' }
              },
              :base => auth[:ldap]['base'],
              :auth => {
                :method => :simple,
                :username => "#{auth[:ldap]['user_object']}=#{username_str},#{auth[:ldap]['base']}",
                :password => password_str
              }
            )

            if ldap.bind
              return true
            end
        end

        return false
      end

      def mean(list)
        s = list.map(&:to_f).reduce(:+).to_f
        (s > 0 && list.length > 0) ? s / list.length.to_f : 0
      end

      def validate_date_str(date_str)
        /^\d{4}-\d{2}-\d{2}$/ === date_str
      end

      def hostname_shorten(hostname, domain=nil)
        if domain && hostname =~ /^\w+\.#{domain}$/
          hostname = hostname[/[^\.]+/]
        end

        hostname
      end

      def get_task_times(backend, task, date_str)
        backend.hvals("vmpooler__#{task}__" + date_str).map(&:to_f)
      end

      def get_capacity_metrics(pools, backend)
        capacity = {
            current: 0,
            total:   0,
            percent: 0
        }

        pools.each do |pool|
          pool['capacity'] = backend.scard('vmpooler__ready__' + pool['name']).to_i

          capacity[:current] += pool['capacity']
          capacity[:total]   += pool['size'].to_i
        end

        if capacity[:total] > 0
          capacity[:percent] = ((capacity[:current].to_f / capacity[:total].to_f) * 100.0).round(1)
        end

        capacity
      end

      def get_queue_metrics(pools, backend)
        queue = {
            pending:   0,
            cloning:   0,
            booting:   0,
            ready:     0,
            running:   0,
            completed: 0,
            total:     0
        }

        pools.each do |pool|
          queue[:pending]   += backend.scard('vmpooler__pending__' + pool['name']).to_i
          queue[:ready]     += backend.scard('vmpooler__ready__' + pool['name']).to_i
          queue[:running]   += backend.scard('vmpooler__running__' + pool['name']).to_i
          queue[:completed] += backend.scard('vmpooler__completed__' + pool['name']).to_i
        end

        queue[:cloning] = backend.get('vmpooler__tasks__clone').to_i
        queue[:booting] = queue[:pending].to_i - queue[:cloning].to_i
        queue[:booting] = 0 if queue[:booting] < 0
        queue[:total]   = queue[:pending].to_i + queue[:ready].to_i + queue[:running].to_i + queue[:completed].to_i

        queue
      end

      def get_tag_metrics(backend, date_str)
        tags = {}

        backend.hgetall('vmpooler__tag__' + date_str).each do |key, value|
          hostname = 'unknown'
          tag = 'unknown'

          if key =~ /\:/
            hostname, tag = key.split(':', 2)
          end

          tags[tag] ||= {}
          tags[tag][value] ||= 0
          tags[tag][value] += 1

          tags[tag]['total'] ||= 0
          tags[tag]['total'] += 1
        end

        tags
      end

      def get_task_metrics(backend, task_str, date_str, opts = {})
        opts = {:bypool => false}.merge(opts)

        task = {
            duration: {
                average: 0,
                min:     0,
                max:     0,
                total:   0
            },
            count:    {
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

        task
      end

    end
  end
end
