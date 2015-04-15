module Vmpooler

  class API

    module Helpers

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

      def get_task_times(redis, task, date_str)
        redis.hvals("vmpooler__#{task}__" + date_str).map(&:to_f)
      end

      def get_capacity_metrics(pools, redis)
        capacity = {
            current: 0,
            total:   0,
            percent: 0
        }

        pools.each do |pool|
          pool['capacity'] = redis.scard('vmpooler__ready__' + pool['name']).to_i

          capacity[:current] += pool['capacity']
          capacity[:total]   += pool['size'].to_i
        end

        if capacity[:total] > 0
          capacity[:percent] = ((capacity[:current].to_f / capacity[:total].to_f) * 100.0).round(1)
        end

        capacity
      end

      def get_queue_metrics(pools, redis)
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
          queue[:pending]   += redis.scard('vmpooler__pending__' + pool['name']).to_i
          queue[:ready]     += redis.scard('vmpooler__ready__' + pool['name']).to_i
          queue[:running]   += redis.scard('vmpooler__running__' + pool['name']).to_i
          queue[:completed] += redis.scard('vmpooler__completed__' + pool['name']).to_i
        end

        queue[:cloning] = redis.get('vmpooler__tasks__clone').to_i
        queue[:booting] = queue[:pending].to_i - queue[:cloning].to_i
        queue[:booting] = 0 if queue[:booting] < 0
        queue[:total]   = queue[:pending].to_i + queue[:ready].to_i + queue[:running].to_i + queue[:completed].to_i

        queue
      end

      def get_task_metrics(redis, task_str, date_str, opts = {})
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

        task[:count][:total] = redis.hlen('vmpooler__' + task_str + '__' + date_str).to_i

        if task[:count][:total] > 0
          if opts[:bypool] == true
            task_times_bypool = {}

            task[:count][:pool]    = {}
            task[:duration][:pool] = {}

            redis.hgetall('vmpooler__' + task_str + '__' + date_str).each do |key, value|
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

          task_times = get_task_times(redis, task_str, date_str)

          task[:duration][:total]                      = task_times.reduce(:+).to_f
          task[:duration][:average]                    = (task[:duration][:total] / task[:count][:total]).round(1)
          task[:duration][:min], task[:duration][:max] = task_times.minmax
        end

        task
      end

    end
  end
end
