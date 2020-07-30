# frozen_string_literal: true

require 'vmpooler/util/parsing'

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

    def metrics
      Vmpooler::API.settings.metrics
    end

    def config
      Vmpooler::API.settings.config[:config]
    end

    def pools
      Vmpooler::API.settings.config[:pools]
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
      result = []
      aliases = Vmpooler::API.settings.config[:alias]
      if aliases
        result += aliases[template] if aliases[template].is_a?(Array)
        template_backends << aliases[template] if aliases[template].is_a?(String)
      end
      result
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

        pickup = Pickup.new(weighted_pools) if weighted_pools.count == template_backends.count
        count.to_i.times do
          if pickup
            selection << pickup.pick
          else
            selection << template_backends.sample
          end
        end
      else
        count.to_i.times do
          selection << template
        end
      end

      count_selection(selection)
    end

    def fetch_single_vm(template)
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

          vms.reverse.each do |vm|
            ready = vm_ready?(vm, config['domain'])
            if ready
              smoved = backend.smove("vmpooler__ready__#{template_backend}", "vmpooler__running__#{template_backend}", vm)
              if smoved
                return [vm, template_backend, template]
              else
                metrics.increment("checkout.smove.failed.#{template_backend}")
                return [nil, nil, nil]
              end
            else
              backend.smove("vmpooler__ready__#{template_backend}", "vmpooler__completed__#{template_backend}", vm)
              metrics.increment("checkout.nonresponsive.#{template_backend}")
            end
          end
        end
        [nil, nil, nil]
      end
    end

    def return_vm_to_ready_state(template, vm)
      backend.smove("vmpooler__running__#{template}", "vmpooler__ready__#{template}", vm)
    end

    def account_for_starting_vm(template, vm)
      backend.sadd("vmpooler__migrating__#{template}", vm)
      backend.hset("vmpooler__active__#{template}", vm, Time.now)
      backend.hset("vmpooler__vm__#{vm}", 'checkout', Time.now)

      if Vmpooler::API.settings.config[:auth] and has_token?
        validate_token(backend)

        backend.hset('vmpooler__vm__' + vm, 'token:token', request.env['HTTP_X_AUTH_TOKEN'])
        backend.hset('vmpooler__vm__' + vm, 'token:user',
                     backend.hget('vmpooler__token__' + request.env['HTTP_X_AUTH_TOKEN'], 'user')
        )

        if config['vm_lifetime_auth'].to_i > 0
          backend.hset('vmpooler__vm__' + vm, 'lifetime', config['vm_lifetime_auth'].to_i)
        end
      end
    end

    def update_result_hosts(result, template, vm)
      result[template] ||= {}
      if result[template]['hostname']
        result[template]['hostname'] = Array(result[template]['hostname'])
        result[template]['hostname'].push(vm)
      else
        result[template]['hostname'] = vm
      end
    end

    def atomically_allocate_vms(payload)
      result = { 'ok' => false }
      failed = false
      vms = []

      payload.each do |requested, count|
        count.to_i.times do |_i|
          vmname, vmpool, vmtemplate = fetch_single_vm(requested)
          if !vmname
            failed = true
            metrics.increment('checkout.empty.' + requested)
            break
          else
            vms << [vmpool, vmname, vmtemplate]
            metrics.increment('checkout.success.' + vmtemplate)
          end
        end
      end

      if failed
        vms.each do |(vmpool, vmname, _vmtemplate)|
          return_vm_to_ready_state(vmpool, vmname)
        end
        status 503
      else
        vms.each do |(vmpool, vmname, vmtemplate)|
          account_for_starting_vm(vmpool, vmname)
          update_result_hosts(result, vmtemplate, vmname)
        end

        result['ok'] = true
        result['domain'] = config['domain'] if config['domain']
      end

      result
    end

    def update_pool_size(payload)
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

    def update_pool_template(payload)
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

    def reset_pool(payload)
      result = { 'ok' => false }

      payload.each do |poolname, _count|
        backend.sadd('vmpooler__poolreset', poolname)
      end
      status 201
      result['ok'] = true
      result
    end

    def update_clone_target(payload)
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

    def sync_pool_templates
      pool_index = pool_index(pools)
      template_configs = backend.hgetall('vmpooler__config__template')
      template_configs&.each do |poolname, template|
        next unless pool_index.include? poolname

        pools[pool_index[poolname]]['template'] = template
      end
    end

    def sync_pool_sizes
      pool_index = pool_index(pools)
      poolsize_configs = backend.hgetall('vmpooler__config__poolsize')
      poolsize_configs&.each do |poolname, size|
        next unless pool_index.include? poolname

        pools[pool_index[poolname]]['size'] = size.to_i
      end
    end

    def sync_clone_targets
      pool_index = pool_index(pools)
      clone_target_configs = backend.hgetall('vmpooler__config__clone_target')
      clone_target_configs&.each do |poolname, clone_target|
        next unless pool_index.include? poolname

        pools[pool_index[poolname]]['clone_target'] = clone_target
      end
    end

    def too_many_requested?(payload)
      payload&.each do |poolname, count|
        next unless count.to_i > config['max_ondemand_instances_per_request']

        metrics.increment('ondemandrequest_fail.toomanyrequests.' + poolname)
        return true
      end
      false
    end

    def generate_ondemand_request(payload)
      result = { 'ok': false }

      requested_instances = payload.reject { |k, _v| k == 'request_id' }
      if too_many_requested?(requested_instances)
        result['message'] = "requested amount of instances exceeds the maximum #{config['max_ondemand_instances_per_request']}"
        status 403
        return result
      end

      score = Time.now.to_i
      request_id = payload['request_id']
      request_id ||= generate_request_id
      result['request_id'] = request_id

      if backend.exists?("vmpooler__odrequest__#{request_id}")
        result['message'] = "request_id '#{request_id}' has already been created"
        status 409
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
        backend.hset("vmpooler__odrequest__#{request_id}", 'token:token', request.env['HTTP_X_AUTH_TOKEN'])
        backend.hset("vmpooler__odrequest__#{request_id}", 'token:user',
                     backend.hget('vmpooler__token__' + request.env['HTTP_X_AUTH_TOKEN'], 'user'))
      end

      result['domain'] = config['domain'] if config['domain']
      result[:ok] = true
      metrics.increment('ondemandrequest_generate.success')
      result
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
            if p['alias'].is_a?(Array)
              (p['alias'] & subpool).any?
            elsif p['alias'].is_a?(String)
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
        token = backend.hgetall('vmpooler__token__' + params[:token])

        if not token.nil? and not token.empty?
          status 200

          pools.each do |pool|
            backend.smembers('vmpooler__running__' + pool['name']).each do |vm|
              if backend.hget('vmpooler__vm__' + vm, 'token:token') == params[:token]
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
        backend.hset('vmpooler__token__' + result['token'], 'created', Time.now)

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
              metrics.increment('ondemandrequest_fail.invalid.' + bad_template)
            end
            status 404
          end
        else
          metrics.increment('ondemandrequest_fail.invalid.unknown')
          status 404
        end
      rescue JSON::ParserError
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
            metrics.increment('ondemandrequest_fail.invalid.' + bad_template)
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
            metrics.increment('checkout.invalid.' + bad_template)
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
      payload = {}

      params.split('+').each do |template|
        payload[template] ||= 0
        payload[template] += 1
      end

      payload
    end

    def invalid_templates(payload)
      invalid = []
      payload.keys.each do |template|
        invalid << template unless pool_exists?(template)
      end
      invalid
    end

    def invalid_template_or_size(payload)
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

    def invalid_template_or_path(payload)
      invalid = []
      payload.each do |pool, template|
        invalid << pool unless pool_exists?(pool)
        invalid << pool unless template.include? '/'
        invalid << pool if template[0] == '/'
        invalid << pool if template[-1] == '/'
      end
      invalid
    end

    def invalid_pool(payload)
      invalid = []
      payload.each do |pool, _clone_target|
        invalid << pool unless pool_exists?(pool)
      end
      invalid
    end

    def check_ondemand_request(request_id)
      result = { 'ok' => false }
      request_hash = backend.hgetall("vmpooler__odrequest__#{request_id}")
      if request_hash.empty?
        result['message'] = "no request found for request_id '#{request_id}'"
        return result
      end

      result['request_id'] = request_id
      result['ready'] = false
      result['ok'] = true
      status 202

      if request_hash['status'] == 'ready'
        result['ready'] = true
        Parsing.get_platform_pool_count(request_hash['requested']) do |platform_alias, pool, _count|
          instances = backend.smembers("vmpooler__#{request_id}__#{platform_alias}__#{pool}")

          if result.key?(platform_alias)
            result[platform_alias][:hostname] = result[platform_alias][:hostname] + instances
          else
            result[platform_alias] = { 'hostname': instances }
          end
        end
        result['domain'] = config['domain'] if config['domain']
        status 200
      elsif request_hash['status'] == 'failed'
        result['message'] = "The request failed to provision instances within the configured ondemand_request_ttl '#{config['ondemand_request_ttl']}'"
        status 200
      elsif request_hash['status'] == 'deleted'
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

    def delete_ondemand_request(request_id)
      result = { 'ok' => false }

      platforms = backend.hget("vmpooler__odrequest__#{request_id}", 'requested')
      unless platforms
        result['message'] = "no request found for request_id '#{request_id}'"
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
            metrics.increment('checkout.invalid.' + bad_template)
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

        if config['domain']
          result[params[:hostname]]['domain'] = config['domain']
        end

        result[params[:hostname]]['host'] = rdata['host'] if rdata['host']
        result[params[:hostname]]['migrated'] = rdata['migrated'] if rdata['migrated']

      end

      JSON.pretty_generate(result)
    end

    delete "#{api_prefix}/vm/:hostname/?" do
      content_type :json
      metrics.increment('http_requests_vm_total.delete.vm.hostname')

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
          metrics.increment('delete.success')
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

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if backend.exists?('vmpooler__vm__' + params[:hostname])
        begin
          jdata = JSON.parse(request.body.read)
        rescue StandardError
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
              unless arg.is_a?(Hash)
                failure.push("You provided tags (#{arg}) as something other than a hash.")
              end

              if config['allowed_tags']
                failure.push("You provided unsuppored tags (#{arg}).") if not (arg.keys - config['allowed_tags']).empty?
              end
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

    post "#{api_prefix}/vm/:hostname/disk/:size/?" do
      content_type :json
      metrics.increment('http_requests_vm_total.post.vm.disksize')

      need_token! if Vmpooler::API.settings.config[:auth]

      status 404
      result = { 'ok' => false }

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if ((params[:size].to_i > 0 )and (backend.exists?('vmpooler__vm__' + params[:hostname])))
        result[params[:hostname]] = {}
        result[params[:hostname]]['disk'] = "+#{params[:size]}gb"

        backend.sadd('vmpooler__tasks__disk', params[:hostname] + ':' + params[:size])

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

      params[:hostname] = hostname_shorten(params[:hostname], config['domain'])

      if backend.exists?('vmpooler__vm__' + params[:hostname])
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
      metrics.increment('http_requests_vm_total.post.vm.disksize')

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
  end
  end
end
