# frozen_string_literal: true

require 'vmpooler/util/parsing'
require 'vmpooler/dns'

module Vmpooler
  class API
    class V3 < Sinatra::Base
      api_version = '3'
      api_prefix  = "/api/v#{api_version}"

      helpers do
        include Vmpooler::API::Helpers
      end

      def backend
        Vmpooler::API.settings.redis
      end

      def metrics
        Vmpooler::API.settings.metrics
      end

      def config
        Vmpooler::API.settings.config[:config]
      end

      def full_config
        Vmpooler::API.settings.config
      end

      def pools
        Vmpooler::API.settings.config[:pools]
      end

      def pools_at_startup
        Vmpooler::API.settings.config[:pools_at_startup]
      end

      def pool_exists?(template)
        Vmpooler::API.settings.config[:pool_names].include?(template)
      end

      def need_auth!
        validate_auth(backend)
      end

      def need_token!
        validate_token(backend)
      end

      def checkoutlock
        Vmpooler::API.settings.checkoutlock
      end

      def get_template_aliases(template)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = []
          aliases = Vmpooler::API.settings.config[:alias]
          if aliases
            result += aliases[template] if aliases[template].is_a?(Array)
            template_backends << aliases[template] if aliases[template].is_a?(String)
          end
          result
        end
      end

      def get_pool_weights(template_backends)
        pool_index = pool_index(pools)
        weighted_pools = {}
        template_backends.each do |t|
          next unless pool_index.key? t

          index = pool_index[t]
          clone_target = pools[index]['clone_target'] || config['clone_target']
          next unless config.key?('backend_weight')

          weight = config['backend_weight'][clone_target]
          if weight
            weighted_pools[t] = weight
          end
        end
        weighted_pools
      end

      def count_selection(selection)
        result = {}
        selection.uniq.each do |poolname|
          result[poolname] = selection.count(poolname)
        end
        result
      end

      def evaluate_template_aliases(template, count)
        template_backends = []
        template_backends << template if backend.sismember('vmpooler__pools', template)
        selection = []
        aliases = get_template_aliases(template)
        if aliases
          template_backends += aliases
          weighted_pools = get_pool_weights(template_backends)

          if weighted_pools.count > 1 && weighted_pools.count == template_backends.count
            pickup = Pickup.new(weighted_pools)
            count.to_i.times do
              selection << pickup.pick
            end
          else
            count.to_i.times do
              selection << template_backends.sample
            end
          end
        end

        count_selection(selection)
      end

      # Fetch a single vm from a pool
      #
      # @param [String] template
      #   The template that the vm should be created from
      #
      # @return [Tuple] vmname, vmpool, vmtemplate
      #   Returns a tuple containing the vm's name, the pool it came from, and
      #   what template was used, if successful. Otherwise the tuple contains.
      #   nil values.
      def fetch_single_vm(template)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          template_backends = [template]
          aliases = Vmpooler::API.settings.config[:alias]
          if aliases
            template_backends += aliases[template] if aliases[template].is_a?(Array)
            template_backends << aliases[template] if aliases[template].is_a?(String)
            pool_index = pool_index(pools)
            weighted_pools = {}
            template_backends.each do |t|
              next unless pool_index.key? t

              index = pool_index[t]
              clone_target = pools[index]['clone_target'] || config['clone_target']
              next unless config.key?('backend_weight')

              weight = config['backend_weight'][clone_target]
              if weight
                weighted_pools[t] = weight
              end
            end

            if weighted_pools.count == template_backends.count
              pickup = Pickup.new(weighted_pools)
              selection = pickup.pick
              template_backends.delete(selection)
              template_backends.unshift(selection)
            else
              first = template_backends.sample
              template_backends.delete(first)
              template_backends.unshift(first)
            end
          end

          checkoutlock.synchronize do
            template_backends.each do |template_backend|
              vms = backend.smembers("vmpooler__ready__#{template_backend}")
              next if vms.empty?

              vm = vms.pop
              smoved = backend.smove("vmpooler__ready__#{template_backend}", "vmpooler__running__#{template_backend}", vm)
              if smoved
                return [vm, template_backend, template]
              end
            end
            [nil, nil, nil]
          end
        end
      end

      def return_vm_to_ready_state(template, vm)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          backend.srem("vmpooler__migrating__#{template}", vm)
          backend.hdel("vmpooler__active__#{template}", vm)
          backend.hdel("vmpooler__vm__#{vm}", 'checkout', 'token:token', 'token:user')
          backend.smove("vmpooler__running__#{template}", "vmpooler__ready__#{template}", vm)
        end
      end

      def account_for_starting_vm(template, vm)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          user = backend.hget("vmpooler__token__#{request.env['HTTP_X_AUTH_TOKEN']}", 'user')
          span.set_attribute('enduser.id', user)
          has_token_result = has_token?
          backend.sadd("vmpooler__migrating__#{template}", vm)
          backend.hset("vmpooler__active__#{template}", vm, Time.now)
          backend.hset("vmpooler__vm__#{vm}", 'checkout', Time.now)

          if Vmpooler::API.settings.config[:auth] and has_token_result
            backend.hset("vmpooler__vm__#{vm}", 'token:token', request.env['HTTP_X_AUTH_TOKEN'])
            backend.hset("vmpooler__vm__#{vm}", 'token:user', user)

            if config['vm_lifetime_auth'].to_i > 0
              backend.hset("vmpooler__vm__#{vm}", 'lifetime', config['vm_lifetime_auth'].to_i)
            end
          end
        end
      end

      def update_result_hosts(result, template, vm)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result[template] ||= {}
          if result[template]['hostname']
            result[template]['hostname'] = Array(result[template]['hostname'])
            result[template]['hostname'].push(vm)
          else
            result[template]['hostname'] = vm
          end
        end
      end

      def atomically_allocate_vms(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          result = { 'ok' => false }
          failed = false
          vms = [] # vmpool, vmname, vmtemplate

          validate_token(backend) if Vmpooler::API.settings.config[:auth] and has_token?

          payload.each do |requested, count|
            count.to_i.times do |_i|
              vmname, vmpool, vmtemplate = fetch_single_vm(requested)
              if vmname
                account_for_starting_vm(vmpool, vmname)
                vms << [vmpool, vmname, vmtemplate]
                metrics.increment("checkout.success.#{vmpool}")
                update_user_metrics('allocate', vmname) if Vmpooler::API.settings.config[:config]['usage_stats']
              else
                failed = true
                metrics.increment("checkout.empty.#{requested}")
                break
              end
            end
          end

          if failed
            vms.each do |(vmpool, vmname, _vmtemplate)|
              return_vm_to_ready_state(vmpool, vmname)
            end
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V3.atomically_allocate_vms',
              'error.message' => '503 due to failing to allocate one or more vms'
            })
            status 503
          else
            vm_names = []
            vms.each do |(vmpool, vmname, vmtemplate)|
              vmdomain = Dns.get_domain_for_pool(full_config, vmpool)
              vmfqdn = "#{vmname}.#{vmdomain}"
              update_result_hosts(result, vmtemplate, vmfqdn)
              vm_names.append(vmfqdn)
            end

            span.set_attribute('vmpooler.vm_names', vm_names.join(',')) unless vm_names.empty?

            result['ok'] = true
          end

          result
        end
      end

      def component_to_test(match, labels_string)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          return if labels_string.nil?

          labels_string_parts = labels_string.split(',')
          labels_string_parts.each do |part|
            key, value = part.split('=')
            next if value.nil?
            return value if key == match
          end
          'none'
        end
      end

      def update_user_metrics(operation, vmname)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          begin
            backend.multi
            backend.hget("vmpooler__vm__#{vmname}", 'tag:jenkins_build_url')
            backend.hget("vmpooler__vm__#{vmname}", 'token:user')
            backend.hget("vmpooler__vm__#{vmname}", 'template')
            jenkins_build_url, user, poolname = backend.exec
            poolname = poolname.gsub('.', '_')

            if user
              user = user.gsub('.', '_')
            else
              user = 'unauthenticated'
            end
            metrics.increment("user.#{user}.#{operation}.#{poolname}")

            if jenkins_build_url
              if jenkins_build_url.include? 'litmus'
                # Very simple filter for Litmus jobs - just count them coming through for the moment.
                metrics.increment("usage_litmus.#{user}.#{operation}.#{poolname}")
              else
                url_parts = jenkins_build_url.split('/')[2..]
                jenkins_instance = url_parts[0].gsub('.', '_')
                value_stream_parts = url_parts[2].split('_')
                value_stream_parts = value_stream_parts.map { |s| s.gsub('.', '_') }
                value_stream = value_stream_parts.shift
                branch = value_stream_parts.pop
                project = value_stream_parts.shift
                job_name = value_stream_parts.join('_')
                build_metadata_parts = url_parts[3]
                component_to_test = component_to_test('RMM_COMPONENT_TO_TEST_NAME', build_metadata_parts)

                metrics.increment("usage_jenkins_instance.#{jenkins_instance}.#{value_stream}.#{operation}.#{poolname}")
                metrics.increment("usage_branch_project.#{branch}.#{project}.#{operation}.#{poolname}")
                metrics.increment("usage_job_component.#{job_name}.#{component_to_test}.#{operation}.#{poolname}")
              end
            end
          rescue StandardError => e
            puts 'd', "[!] [#{poolname}] failed while evaluating usage labels on '#{vmname}' with an error: #{e}"
            span.record_exception(e)
            span.status = OpenTelemetry::Trace::Status.error(e.to_s)
            span.add_event('log', attributes: {
              'log.severity' => 'debug',
              'log.message' => "[#{poolname}] failed while evaluating usage labels on '#{vmname}' with an error: #{e}"
            })
          end
        end
      end

      def reset_pool_size(poolname)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          pool_index = pool_index(pools)

          pools_updated = 0
          sync_pool_sizes

          pool_size_now = pools[pool_index[poolname]]['size'].to_i
          pool_size_original = pools_at_startup[pool_index[poolname]]['size'].to_i
          result['pool_size_before_reset'] = pool_size_now
          result['pool_size_before_overrides'] = pool_size_original

          unless pool_size_now == pool_size_original
            pools[pool_index[poolname]]['size'] = pool_size_original
            backend.hdel('vmpooler__config__poolsize', poolname)
            backend.sadd('vmpooler__pool__undo_size_override', poolname)
            pools_updated += 1
            status 201
          end

          status 200 unless pools_updated > 0
          result['ok'] = true
          result
        end
      end

      def update_pool_size(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          pool_index = pool_index(pools)
          pools_updated = 0
          sync_pool_sizes

          payload.each do |poolname, size|
            unless pools[pool_index[poolname]]['size'] == size.to_i
              pools[pool_index[poolname]]['size'] = size.to_i
              backend.hset('vmpooler__config__poolsize', poolname, size)
              pools_updated += 1
              status 201
            end
          end
          status 200 unless pools_updated > 0
          result['ok'] = true
          result
        end
      end

      def reset_pool_template(poolname)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          pool_index_live = pool_index(pools)
          pool_index_original = pool_index(pools_at_startup)

          pools_updated = 0
          sync_pool_templates

          template_now = pools[pool_index_live[poolname]]['template']
          template_original = pools_at_startup[pool_index_original[poolname]]['template']
          result['template_before_reset'] = template_now
          result['template_before_overrides'] = template_original

          unless template_now == template_original
            pools[pool_index_live[poolname]]['template'] = template_original
            backend.hdel('vmpooler__config__template', poolname)
            backend.sadd('vmpooler__pool__undo_template_override', poolname)
            pools_updated += 1
            status 201
          end

          status 200 unless pools_updated > 0
          result['ok'] = true
          result
        end
      end

      def update_pool_template(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          pool_index = pool_index(pools)
          pools_updated = 0
          sync_pool_templates

          payload.each do |poolname, template|
            unless pools[pool_index[poolname]]['template'] == template
              pools[pool_index[poolname]]['template'] = template
              backend.hset('vmpooler__config__template', poolname, template)
              pools_updated += 1
              status 201
            end
          end
          status 200 unless pools_updated > 0
          result['ok'] = true
          result
        end
      end

      def reset_pool(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          payload.each do |poolname, _count|
            backend.sadd('vmpooler__poolreset', poolname)
          end
          status 201
          result['ok'] = true
          result
        end
      end

      def update_clone_target(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          result = { 'ok' => false }

          pool_index = pool_index(pools)
          pools_updated = 0
          sync_clone_targets

          payload.each do |poolname, clone_target|
            unless pools[pool_index[poolname]]['clone_target'] == clone_target
              pools[pool_index[poolname]]['clone_target'] = clone_target
              backend.hset('vmpooler__config__clone_target', poolname, clone_target)
              pools_updated += 1
              status 201
            end
          end
          status 200 unless pools_updated > 0
          result['ok'] = true
          result
        end
      end

      def sync_pool_templates
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          pool_index = pool_index(pools)
          template_configs = backend.hgetall('vmpooler__config__template')
          template_configs&.each do |poolname, template|
            next unless pool_index.include? poolname

            pools[pool_index[poolname]]['template'] = template
          end
        end
      end

      def sync_pool_sizes
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          pool_index = pool_index(pools)
          poolsize_configs = backend.hgetall('vmpooler__config__poolsize')
          poolsize_configs&.each do |poolname, size|
            next unless pool_index.include? poolname

            pools[pool_index[poolname]]['size'] = size.to_i
          end
        end
      end

      def sync_clone_targets
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          pool_index = pool_index(pools)
          clone_target_configs = backend.hgetall('vmpooler__config__clone_target')
          clone_target_configs&.each do |poolname, clone_target|
            next unless pool_index.include? poolname

            pools[pool_index[poolname]]['clone_target'] = clone_target
          end
        end
      end

      def too_many_requested?(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          payload&.each do |poolname, count|
            next unless count.to_i > config['max_ondemand_instances_per_request']

            metrics.increment("ondemandrequest_fail.toomanyrequests.#{poolname}")
            return true
          end
          false
        end
      end

      def generate_ondemand_request(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          result = { 'ok': false }

          requested_instances = payload.reject { |k, _v| k == 'request_id' }
          if too_many_requested?(requested_instances)
            e_message = "requested amount of instances exceeds the maximum #{config['max_ondemand_instances_per_request']}"
            result['message'] = e_message
            status 403
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V3.generate_ondemand_request',
              'error.message' => "403 due to #{e_message}"
            })
            return result
          end

          score = Time.now.to_i
          request_id = payload['request_id']
          request_id ||= generate_request_id
          result['request_id'] = request_id
          span.set_attribute('vmpooler.request_id', request_id)

          if backend.exists?("vmpooler__odrequest__#{request_id}")
            e_message = "request_id '#{request_id}' has already been created"
            result['message'] = e_message
            status 409
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V3.generate_ondemand_request',
              'error.message' => "409 due to #{e_message}"
            })
            metrics.increment('ondemandrequest_generate.duplicaterequests')
            return result
          end

          status 201

          platforms_with_aliases = []
          requested_instances.each do |poolname, count|
            selection = evaluate_template_aliases(poolname, count)
            selection.map { |selected_pool, selected_pool_count| platforms_with_aliases << "#{poolname}:#{selected_pool}:#{selected_pool_count}" }
          end
          platforms_string = platforms_with_aliases.join(',')

          return result unless backend.zadd('vmpooler__provisioning__request', score, request_id)

          backend.hset("vmpooler__odrequest__#{request_id}", 'requested', platforms_string)
          if Vmpooler::API.settings.config[:auth] and has_token?
            token_token = request.env['HTTP_X_AUTH_TOKEN']
            token_user = backend.hget("vmpooler__token__#{token_token}", 'user')
            backend.hset("vmpooler__odrequest__#{request_id}", 'token:token', token_token)
            backend.hset("vmpooler__odrequest__#{request_id}", 'token:user', token_user)
            span.set_attribute('enduser.id', token_user)
          end

          result[:ok] = true
          metrics.increment('ondemandrequest_generate.success')
          result
        end
      end

      def generate_request_id
        SecureRandom.uuid
      end

      get '/' do
        sync_pool_sizes
        redirect to('/dashboard/')
      end

      # Provide run-time statistics
      #
      # Example:
      #
      # {
      #   "boot": {
      #     "duration": {
      #       "average": 163.6,
      #       "min": 65.49,
      #       "max": 830.07,
      #       "total": 247744.71000000002
      #     },
      #     "count": {
      #       "total": 1514
      #     }
      #   },
      #   "capacity": {
      #     "current": 968,
      #     "total": 975,
      #     "percent": 99.3
      #   },
      #   "clone": {
      #     "duration": {
      #       "average": 17.0,
      #       "min": 4.66,
      #       "max": 637.96,
      #       "total": 25634.15
      #     },
      #     "count": {
      #       "total": 1507
      #     }
      #   },
      #   "queue": {
      #     "pending": 12,
      #     "cloning": 0,
      #     "booting": 12,
      #     "ready": 968,
      #     "running": 367,
      #     "completed": 0,
      #     "total": 1347
      #   },
      #   "pools": {
      #     "ready": 100,
      #     "running": 120,
      #     "pending": 5,
      #     "max": 250,
      #   }
      #   "status": {
      #     "ok": true,
      #     "message": "Battle station fully armed and operational.",
      #     "empty": [ # NOTE: would not have 'ok: true' w/ "empty" pools
      #       "redhat-7-x86_64",
      #       "ubuntu-1404-i386"
      #     ],
      #     "uptime": 179585.9
      # }
      #
      # If the query parameter 'view' is provided, it will be used to select which top level
      # element to compute and return. Select them by specifying them in a comma separated list.
      # For example /status?view=capacity,boot
      # would return only the "capacity" and "boot" statistics. "status" is always returned

      get "#{api_prefix}/status/?" do
        content_type :json

        if params[:view]
          views = params[:view].split(",")
        end

        result = {
          status: {
            ok: true,
            message: 'Battle station fully armed and operational.'
          }
        }

        sync_pool_sizes

        result[:capacity] = get_capacity_metrics(pools, backend) unless views and not views.include?("capacity")
        result[:queue] = get_queue_metrics(pools, backend) unless views and not views.include?("queue")
        result[:clone] = get_task_metrics(backend, 'clone', Date.today.to_s) unless views and not views.include?("clone")
        result[:boot] = get_task_metrics(backend, 'boot', Date.today.to_s) unless views and not views.include?("boot")

        # Check for empty pools
        result[:pools] = {} unless views and not views.include?("pools")
        ready_hash = get_list_across_pools_redis_scard(pools, 'vmpooler__ready__', backend)
        running_hash = get_list_across_pools_redis_scard(pools, 'vmpooler__running__', backend)
        pending_hash = get_list_across_pools_redis_scard(pools, 'vmpooler__pending__', backend)
        lastBoot_hash = get_list_across_pools_redis_hget(pools, 'vmpooler__lastboot', backend)

        unless views and not views.include?("pools")
          pools.each do |pool|
            # REMIND: move this out of the API and into the back-end
            ready    = ready_hash[pool['name']]
            running  = running_hash[pool['name']]
            pending  = pending_hash[pool['name']]
            max      = pool['size']
            lastBoot = lastBoot_hash[pool['name']]
            aka      = pool['alias']

            result[:pools][pool['name']] = {
              ready: ready,
              running: running,
              pending: pending,
              max: max,
              lastBoot: lastBoot
            }

            if aka
              result[:pools][pool['name']][:alias] = aka
            end

            # for backwards compatibility, include separate "empty" stats in "status" block
            if ready == 0 && max != 0
              result[:status][:empty] ||= []
              result[:status][:empty].push(pool['name'])

              result[:status][:ok] = false
              result[:status][:message] = "Found #{result[:status][:empty].length} empty pools."
            end
          end
        end

        result[:status][:uptime] = (Time.now - Vmpooler::API.settings.config[:uptime]).round(1) if Vmpooler::API.settings.config[:uptime]

        JSON.pretty_generate(Hash[result.sort_by { |k, _v| k }])
      end

      # request statistics for specific pools by passing parameter 'pool'
      # with a coma separated list of pools we want to query ?pool=ABC,DEF
      # returns the ready, max numbers and the aliases (if set)
      get "#{api_prefix}/poolstat/?" do
        content_type :json

        result = {}

        poolscopy = []

        if params[:pool]
          subpool = params[:pool].split(",")
          poolscopy = pools.select do |p|
            if subpool.include?(p['name'])
              true
            elsif !p['alias'].nil?
              if p['alias'].instance_of?(Array)
                (p['alias'] & subpool).any?
              elsif p['alias'].instance_of?(String)
                subpool.include?(p['alias'])
              end
            end
          end
        end

        result[:pools] = {}

        poolscopy.each do |pool|
          result[:pools][pool['name']] = {}

          max      = pool['size']
          aka      = pool['alias']

          result[:pools][pool['name']][:max] = max

          if aka
            result[:pools][pool['name']][:alias] = aka
          end
        end

        ready_hash = get_list_across_pools_redis_scard(poolscopy, 'vmpooler__ready__', backend)

        ready_hash.each { |k, v| result[:pools][k][:ready] = v }

        JSON.pretty_generate(Hash[result.sort_by { |k, _v| k }])
      end

      # requests the total number of running VMs
      get "#{api_prefix}/totalrunning/?" do
        content_type :json
        queue = {
            running: 0
        }

        queue[:running] = get_total_across_pools_redis_scard(pools, 'vmpooler__running__', backend)

        JSON.pretty_generate(queue)
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
              span = OpenTelemetry::Trace.current_span
              span.set_attribute('enduser.id', data['user'])
              token = key.split('__').last

              result[token] ||= {}

              result[token]['created'] = data['created']
              result[token]['last'] = data['last'] || 'never'

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
          token = backend.hgetall("vmpooler__token__#{params[:token]}")

          if not token.nil? and not token.empty?
            status 200

            pools.each do |pool|
              backend.smembers("vmpooler__running__#{pool['name']}").each do |vm|
                if backend.hget("vmpooler__vm__#{vm}", 'token:token') == params[:token]
                  token['vms'] ||= {}
                  token['vms']['running'] ||= []
                  token['vms']['running'].push(vm)
                end
              end
            end

            result = { 'ok' => true, params[:token] => token }
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

          if backend.del("vmpooler__token__#{params[:token]}").to_i > 0
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

          backend.hset("vmpooler__token__#{result['token']}", 'user', @auth.username)
          backend.hset("vmpooler__token__#{result['token']}", 'created', Time.now)
          span = OpenTelemetry::Trace.current_span
          span.set_attribute('enduser.id', @auth.username)

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

      post "#{api_prefix}/ondemandvm/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.post.ondemand.requestid')

        need_token! if Vmpooler::API.settings.config[:auth]

        result = { 'ok' => false }

        begin
          payload = JSON.parse(request.body.read)

          if payload
            invalid = invalid_templates(payload.reject { |k, _v| k == 'request_id' })
            if invalid.empty?
              result = generate_ondemand_request(payload)
            else
              result[:bad_templates] = invalid
              invalid.each do |bad_template|
                metrics.increment("ondemandrequest_fail.invalid.#{bad_template}")
              end
              status 404
            end
          else
            metrics.increment('ondemandrequest_fail.invalid.unknown')
            status 404
          end
        rescue JSON::ParserError
          span = OpenTelemetry::Trace.current_span
          span.status = OpenTelemetry::Trace::Status.error('JSON payload could not be parsed')
          status 400
          result = {
            'ok' => false,
            'message' => 'JSON payload could not be parsed'
          }
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/ondemandvm/:template/?" do
        content_type :json
        result = { 'ok' => false }
        metrics.increment('http_requests_vm_total.delete.ondemand.template')

        need_token! if Vmpooler::API.settings.config[:auth]

        payload = extract_templates_from_query_params(params[:template])

        if payload
          invalid = invalid_templates(payload.reject { |k, _v| k == 'request_id' })
          if invalid.empty?
            result = generate_ondemand_request(payload)
          else
            result[:bad_templates] = invalid
            invalid.each do |bad_template|
              metrics.increment("ondemandrequest_fail.invalid.#{bad_template}")
            end
            status 404
          end
        else
          metrics.increment('ondemandrequest_fail.invalid.unknown')
          status 404
        end

        JSON.pretty_generate(result)
      end

      get "#{api_prefix}/ondemandvm/:requestid/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.get.ondemand.request')

        status 404
        result = check_ondemand_request(params[:requestid])

        JSON.pretty_generate(result)
      end

      delete "#{api_prefix}/ondemandvm/:requestid/?" do
        content_type :json
        need_token! if Vmpooler::API.settings.config[:auth]
        metrics.increment('http_requests_vm_total.delete.ondemand.request')

        status 404
        result = delete_ondemand_request(params[:requestid])

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/vm/?" do
        content_type :json
        result = { 'ok' => false }
        metrics.increment('http_requests_vm_total.post.vm.checkout')

        payload = JSON.parse(request.body.read)

        if payload
          invalid = invalid_templates(payload)
          if invalid.empty?
            result = atomically_allocate_vms(payload)
          else
            invalid.each do |bad_template|
              metrics.increment("checkout.invalid.#{bad_template}")
            end
            status 404
          end
        else
          metrics.increment('checkout.invalid.unknown')
          status 404
        end

        JSON.pretty_generate(result)
      end

      def extract_templates_from_query_params(params)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          payload = {}

          params.split('+').each do |template|
            payload[template] ||= 0
            payload[template] += 1
          end

          payload
        end
      end

      def invalid_templates(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          invalid = []
          payload.keys.each do |template|
            invalid << template unless pool_exists?(template)
          end
          invalid
        end
      end

      def invalid_template_or_size(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          invalid = []
          payload.each do |pool, size|
            invalid << pool unless pool_exists?(pool)
            unless is_integer?(size)
              invalid << pool
              next
            end
            invalid << pool unless Integer(size) >= 0
          end
          invalid
        end
      end

      def invalid_template_or_path(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          invalid = []
          payload.each do |pool, template|
            invalid << pool unless pool_exists?(pool)
            invalid << pool unless template.include? '/'
            invalid << pool if template[0] == '/'
            invalid << pool if template[-1] == '/'
          end
          invalid
        end
      end

      def invalid_pool(payload)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do
          invalid = []
          payload.each do |pool, _clone_target|
            invalid << pool unless pool_exists?(pool)
          end
          invalid
        end
      end

      def delete_ondemand_request(request_id)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          span.set_attribute('vmpooler.request_id', request_id)
          result = { 'ok' => false }

          platforms = backend.hget("vmpooler__odrequest__#{request_id}", 'requested')
          unless platforms
            e_message = "no request found for request_id '#{request_id}'"
            result['message'] = e_message
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V3.delete_ondemand_request',
              'error.message' => e_message
            })
            return result
          end

          if backend.hget("vmpooler__odrequest__#{request_id}", 'status') == 'deleted'
            result['message'] = 'the request has already been deleted'
          else
            backend.hset("vmpooler__odrequest__#{request_id}", 'status', 'deleted')

            Parsing.get_platform_pool_count(platforms) do |platform_alias, pool, _count|
              backend.smembers("vmpooler__#{request_id}__#{platform_alias}__#{pool}")&.each do |vm|
                backend.smove("vmpooler__running__#{pool}", "vmpooler__completed__#{pool}", vm)
              end
              backend.del("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
            end
            backend.expire("vmpooler__odrequest__#{request_id}", 129_600_0)
          end
          status 200
          result['ok'] = true
          result
        end
      end

      post "#{api_prefix}/vm/:template/?" do
        content_type :json
        result = { 'ok' => false }
        metrics.increment('http_requests_vm_total.get.vm.template')

        payload = extract_templates_from_query_params(params[:template])

        if payload
          invalid = invalid_templates(payload)
          if invalid.empty?
            result = atomically_allocate_vms(payload)
          else
            invalid.each do |bad_template|
              metrics.increment("checkout.invalid.#{bad_template}")
            end
            status 404
          end
        else
          metrics.increment('checkout.invalid.unknown')
          status 404
        end

        JSON.pretty_generate(result)
      end

      get "#{api_prefix}/vm/:hostname/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.get.vm.hostname')

        result = {}

        status 404
        result['ok'] = false

        params[:hostname] = hostname_shorten(params[:hostname])

        rdata = backend.hgetall("vmpooler__vm__#{params[:hostname]}")
        unless rdata.empty?
          status 200
          result['ok'] = true

          result[params[:hostname]] = {}

          result[params[:hostname]]['template'] = rdata['template']
          result[params[:hostname]]['lifetime'] = (rdata['lifetime'] || config['vm_lifetime']).to_i

          if rdata['destroy']
            result[params[:hostname]]['running'] = ((Time.parse(rdata['destroy']) - Time.parse(rdata['checkout'])) / 60 / 60).round(2) if rdata['checkout']
            result[params[:hostname]]['state'] = 'destroyed'
          elsif rdata['checkout']
            result[params[:hostname]]['running'] = ((Time.now - Time.parse(rdata['checkout'])) / 60 / 60).round(2)
            result[params[:hostname]]['remaining'] = ((Time.parse(rdata['checkout']) + rdata['lifetime'].to_i*60*60 - Time.now) / 60 / 60).round(2)
            result[params[:hostname]]['start_time'] = Time.parse(rdata['checkout']).to_datetime.rfc3339
            result[params[:hostname]]['end_time'] = (Time.parse(rdata['checkout']) + rdata['lifetime'].to_i*60*60).to_datetime.rfc3339
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

          if rdata['disk']
            result[params[:hostname]]['disk'] = rdata['disk'].split(':')
          end

          # Look up IP address of the hostname
          begin
            ipAddress = TCPSocket.gethostbyname(params[:hostname])[3]
          rescue StandardError
            ipAddress = ""
          end

          result[params[:hostname]]['ip'] = ipAddress

          if rdata['pool']
            vmdomain = Dns.get_domain_for_pool(full_config, rdata['pool'])
            if vmdomain
              result[params[:hostname]]['fqdn'] = "#{params[:hostname]}.#{vmdomain}"
            end
          end

          result[params[:hostname]]['host'] = rdata['host'] if rdata['host']
          result[params[:hostname]]['migrated'] = rdata['migrated'] if rdata['migrated']

        end

        JSON.pretty_generate(result)
      end

      def check_ondemand_request(request_id)
        tracer.in_span("Vmpooler::API::V3.#{__method__}") do |span|
          span.set_attribute('vmpooler.request_id', request_id)
          result = { 'ok' => false }
          request_hash = backend.hgetall("vmpooler__odrequest__#{request_id}")
          if request_hash.empty?
            e_message = "no request found for request_id '#{request_id}'"
            result['message'] = e_message
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V3.check_ondemand_request',
              'error.message' => e_message
            })
            return result
          end

          result['request_id'] = request_id
          result['ready'] = false
          result['ok'] = true
          status 202

          case request_hash['status']
          when 'ready'
            result['ready'] = true
            Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, _count|
              instances = backend.smembers("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
              domain = Dns.get_domain_for_pool(full_config, pool)
              instances.map! { |instance| instance.concat(".#{domain}") }

              if result.key?(platform_alias)
                result[platform_alias][:hostname] = result[platform_alias][:hostname] + instances
              else
                result[platform_alias] = { 'hostname': instances }
              end
            end
            status 200
          when 'failed'
            result['message'] = "The request failed to provision instances within the configured ondemand_request_ttl '#{config['ondemand_request_ttl']}'"
            status 200
          when 'deleted'
            result['message'] = 'The request has been deleted'
            status 200
          else
            Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, count|
              instance_count = backend.scard("vmpooler__#{request_id}__#{platform_alias}__#{pool}")
              instances_pending = count.to_i - instance_count.to_i

              if result.key?(platform_alias) && result[platform_alias].key?(:ready)
                result[platform_alias][:ready] = (result[platform_alias][:ready].to_i + instance_count).to_s
                result[platform_alias][:pending] = (result[platform_alias][:pending].to_i + instances_pending).to_s
              else
                result[platform_alias] = {
                  'ready': instance_count.to_s,
                  'pending': instances_pending.to_s
                }
              end
            end
          end

          result
        end
      end

      delete "#{api_prefix}/vm/:hostname/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.delete.vm.hostname')

        result = {}

        status 404
        result['ok'] = false

        params[:hostname] = hostname_shorten(params[:hostname])

        rdata = backend.hgetall("vmpooler__vm__#{params[:hostname]}")
        unless rdata.empty?
          need_token! if rdata['token:token']

          if backend.srem("vmpooler__running__#{rdata['template']}", params[:hostname])
            backend.sadd("vmpooler__completed__#{rdata['template']}", params[:hostname])

            status 200
            result['ok'] = true
            metrics.increment('delete.success')
            update_user_metrics('destroy', params[:hostname]) if Vmpooler::API.settings.config[:config]['usage_stats']
          else
            metrics.increment('delete.failed')
          end
        end

        JSON.pretty_generate(result)
      end

      put "#{api_prefix}/vm/:hostname/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.put.vm.modify')

        status 404
        result = { 'ok' => false }

        failure = []

        params[:hostname] = hostname_shorten(params[:hostname])

        if backend.exists?("vmpooler__vm__#{params[:hostname]}")
          begin
            jdata = JSON.parse(request.body.read)
          rescue StandardError => e
            span = OpenTelemetry::Trace.current_span
            span.record_exception(e)
            span.status = OpenTelemetry::Trace::Status.error(e.to_s)
            halt 400, JSON.pretty_generate(result)
          end

          # Validate data payload
          jdata.each do |param, arg|
            case param
              when 'lifetime'
                need_token! if Vmpooler::API.settings.config[:auth]

                # in hours, defaults to one week
                max_lifetime_upper_limit = config['max_lifetime_upper_limit']
                if max_lifetime_upper_limit
                  max_lifetime_upper_limit = max_lifetime_upper_limit.to_i
                  if arg.to_i >= max_lifetime_upper_limit
                    failure.push("You provided a lifetime (#{arg}) that exceeds the configured maximum of #{max_lifetime_upper_limit}.")
                  end
                end

                # validate lifetime is within boundaries
                unless arg.to_i > 0
                  failure.push("You provided a lifetime (#{arg}) but you must provide a positive number.")
                end

              when 'tags'
                failure.push("You provided tags (#{arg}) as something other than a hash.") unless arg.is_a?(Hash)
                failure.push("You provided unsuppored tags (#{arg}).") if config['allowed_tags'] && !(arg.keys - config['allowed_tags']).empty?
              else
                failure.push("Unknown argument #{arg}.")
            end
          end

          if !failure.empty?
            status 400
            result['failure'] = failure
          else
            jdata.each do |param, arg|
              case param
                when 'lifetime'
                  need_token! if Vmpooler::API.settings.config[:auth]

                  arg = arg.to_i

                  backend.hset("vmpooler__vm__#{params[:hostname]}", param, arg)
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

      post "#{api_prefix}/vm/:hostname/disk/:size/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.post.vm.disksize')

        need_token! if Vmpooler::API.settings.config[:auth]

        status 404
        result = { 'ok' => false }

        params[:hostname] = hostname_shorten(params[:hostname])

        if ((params[:size].to_i > 0 )and (backend.exists?("vmpooler__vm__#{params[:hostname]}")))
          result[params[:hostname]] = {}
          result[params[:hostname]]['disk'] = "+#{params[:size]}gb"

          backend.sadd('vmpooler__tasks__disk', "#{params[:hostname]}:#{params[:size]}")

          status 202
          result['ok'] = true
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/vm/:hostname/snapshot/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.post.vm.snapshot')

        need_token! if Vmpooler::API.settings.config[:auth]

        status 404
        result = { 'ok' => false }

        params[:hostname] = hostname_shorten(params[:hostname])

        if backend.exists?("vmpooler__vm__#{params[:hostname]}")
          result[params[:hostname]] = {}

          o = [('a'..'z'), ('0'..'9')].map(&:to_a).flatten
          result[params[:hostname]]['snapshot'] = o[rand(25)] + (0...31).map { o[rand(o.length)] }.join

          backend.sadd('vmpooler__tasks__snapshot', "#{params[:hostname]}:#{result[params[:hostname]]['snapshot']}")

          status 202
          result['ok'] = true
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/vm/:hostname/snapshot/:snapshot/?" do
        content_type :json
        metrics.increment('http_requests_vm_total.post.vm.snapshot')

        need_token! if Vmpooler::API.settings.config[:auth]

        status 404
        result = { 'ok' => false }

        params[:hostname] = hostname_shorten(params[:hostname])

        unless backend.hget("vmpooler__vm__#{params[:hostname]}", "snapshot:#{params[:snapshot]}").to_i.zero?
          backend.sadd('vmpooler__tasks__snapshot-revert', "#{params[:hostname]}:#{params[:snapshot]}")

          status 202
          result['ok'] = true
        end

        JSON.pretty_generate(result)
      end

      delete "#{api_prefix}/config/poolsize/:pool/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          if pool_exists?(params[:pool])
            result = reset_pool_size(params[:pool])
          else
            metrics.increment('config.invalid.unknown')
            status 404
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/config/poolsize/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          payload = JSON.parse(request.body.read)

          if payload
            invalid = invalid_template_or_size(payload)
            if invalid.empty?
              result = update_pool_size(payload)
            else
              invalid.each do |bad_template|
                metrics.increment("config.invalid.#{bad_template}")
              end
              result[:not_configured] = invalid
              status 400
            end
          else
            metrics.increment('config.invalid.unknown')
            status 404
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      delete "#{api_prefix}/config/pooltemplate/:pool/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          if pool_exists?(params[:pool])
            result = reset_pool_template(params[:pool])
          else
            metrics.increment('config.invalid.unknown')
            status 404
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/config/pooltemplate/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          payload = JSON.parse(request.body.read)

          if payload
            invalid = invalid_template_or_path(payload)
            if invalid.empty?
              result = update_pool_template(payload)
            else
              invalid.each do |bad_template|
                metrics.increment("config.invalid.#{bad_template}")
              end
              result[:bad_templates] = invalid
              status 400
            end
          else
            metrics.increment('config.invalid.unknown')
            status 404
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/poolreset/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          begin
            payload = JSON.parse(request.body.read)
            if payload
              invalid = invalid_templates(payload)
              if invalid.empty?
                result = reset_pool(payload)
              else
                invalid.each do |bad_pool|
                  metrics.increment("poolreset.invalid.#{bad_pool}")
                end
                result[:bad_pools] = invalid
                status 400
              end
            else
              metrics.increment('poolreset.invalid.unknown')
              status 404
            end
          rescue JSON::ParserError
            span = OpenTelemetry::Trace.current_span
            span.record_exception(e)
            span.status = OpenTelemetry::Trace::Status.error('JSON payload could not be parsed')
            status 400
            result = {
              'ok' => false,
              'message' => 'JSON payload could not be parsed'
            }
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      post "#{api_prefix}/config/clonetarget/?" do
        content_type :json
        result = { 'ok' => false }

        if config['experimental_features']
          need_token! if Vmpooler::API.settings.config[:auth]

          payload = JSON.parse(request.body.read)

          if payload
            invalid = invalid_pool(payload)
            if invalid.empty?
              result = update_clone_target(payload)
            else
              invalid.each do |bad_template|
                metrics.increment("config.invalid.#{bad_template}")
              end
              result[:bad_templates] = invalid
              status 400
            end
          else
            metrics.increment('config.invalid.unknown')
            status 404
          end
        else
          status 405
        end

        JSON.pretty_generate(result)
      end

      get "#{api_prefix}/config/?" do
        content_type :json
        result = { 'ok' => false }
        status 404

        if pools
          sync_pool_sizes
          sync_pool_templates

          pool_configuration = []
          pools.each do |pool|
            pool['template_ready'] = template_ready?(pool, backend)
            pool_configuration << pool
          end

          result = {
            pool_configuration: pool_configuration,
            status: {
              ok: true
            }
          }

          status 200
        end
        JSON.pretty_generate(result)
      end

      get "#{api_prefix}/full_config/?" do
        content_type :json

        result = {
          full_config: full_config,
          status: {
            ok: true
          }
        }

        status 200
        JSON.pretty_generate(result)
      end
    end
  end
end
