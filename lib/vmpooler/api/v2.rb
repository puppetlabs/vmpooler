# frozen_string_literal: true

require 'vmpooler/api/v1'
module Vmpooler
  class API
    class V2 < Vmpooler::API::V1
      api_version = '2'
      api_prefix  = "/api/v#{api_version}"

      def get_template_aliases(template)
        tracer.in_span("Vmpooler::API::V2.#{__method__}") do
          result = []
          aliases = Vmpooler::API.settings.config[:alias]
          if aliases
            result += aliases[template] if aliases[template].is_a?(Array)
            template_backends << aliases[template] if aliases[template].is_a?(String)
          end
          result
        end
      end

      def get_domain_for_pool(poolname)
        pool_index = pool_index(pools)
        pools[pool_index[poolname]]['domain']
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
        tracer.in_span("Vmpooler::API::V2.#{__method__}") do
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
                vm_domain = get_domain_for_pool(template_backend)
                ready = vm_ready?(vm, vm_domain)
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
      end

      # The domain in the result body will be set to the one associated with the
      # last vm added. The part of the response is only being retained for
      # backwards compatibility as the hostnames are now fqdn's instead of bare
      # hostnames. This change is a result of now being able to specify a domain
      # per pool. If no vm's in the result had a domain sepcified then the
      # domain key will be omitted similar to how it was previously omitted if
      # the global option domain wasn't specified.
      def atomically_allocate_vms(payload)
        tracer.in_span("Vmpooler::API::V2.#{__method__}") do |span|
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
              'error.type' => 'Vmpooler::API::V2.atomically_allocate_vms',
              'error.message' => '503 due to failing to allocate one or more vms'
            })
            status 503
          else
            vm_names = []
            vms.each do |(vmpool, vmname, vmtemplate)|
              vmdomain = get_domain_for_pool(vmpool)
              if vmdomain
                vmfqdn = "#{vmname}.#{vmdomain}"
                update_result_hosts(result, vmtemplate, vmfqdn)
                vm_names.append(vmfqdn)
                result['domain'] = vmdomain
              else
                update_result_hosts(result, vmtemplate, vmname)
                vm_names.append(vmname)
              end
            end

            span.set_attribute('vmpooler.vm_names', vm_names.join(',')) unless vm_names.empty?

            result['ok'] = true
          end

          result
        end
      end

      def generate_ondemand_request(payload)
        tracer.in_span("Vmpooler::API::V2.#{__method__}") do |span|
          result = { 'ok': false }

          requested_instances = payload.reject { |k, _v| k == 'request_id' }
          if too_many_requested?(requested_instances)
            e_message = "requested amount of instances exceeds the maximum #{config['max_ondemand_instances_per_request']}"
            result['message'] = e_message
            status 403
            span.add_event('error', attributes: {
              'error.type' => 'Vmpooler::API::V2.generate_ondemand_request',
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
              'error.type' => 'Vmpooler::API::V2.generate_ondemand_request',
              'error.message' => "409 due to #{e_message}"
            })
            metrics.increment('ondemandrequest_generate.duplicaterequests')
            return result
          end

          status 201

          platforms_with_aliases = []
          requested_instances.each do |poolname, count|
            selection = evaluate_template_aliases(poolname, count)
            selection.map do |selected_pool, selected_pool_count|
              platforms_with_aliases << "#{poolname}:#{selected_pool}:#{selected_pool_count}"
              pool_domain = get_domain_for_pool(selected_pool)
              result['domain'] = pool_domain if pool_domain
            end
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

      # Endpoints that use overridden methods

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

      # Endpoints that only use bits from the V1 api are called here
      # Note that traces will be named based on the route used in the V1 api
      # but the http.url trace attribute will still have the actual requested url in it

      delete "#{api_prefix}/*" do
        versionless_path_info = request.path_info.delete_prefix("#{api_prefix}/")
        request.path_info = "/api/v1/#{versionless_path_info}"
        call env
      end

      get "#{api_prefix}/*" do
        versionless_path_info = request.path_info.delete_prefix("#{api_prefix}/")
        request.path_info = "/api/v1/#{versionless_path_info}"
        call env
      end

      post "#{api_prefix}/*" do
        versionless_path_info = request.path_info.delete_prefix("#{api_prefix}/")
        request.path_info = "/api/v1/#{versionless_path_info}"
        call env
      end

      put "#{api_prefix}/*" do
        versionless_path_info = request.path_info.delete_prefix("#{api_prefix}/")
        request.path_info = "/api/v1/#{versionless_path_info}"
        call env
      end
    end
  end
end
