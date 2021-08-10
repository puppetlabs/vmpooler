# frozen_string_literal: true

require 'prometheus/client'

module Vmpooler
  class Metrics
    class Promstats < Metrics
      attr_reader :prefix, :prometheus_endpoint, :prometheus_prefix

      # Constants for Metric Types
      M_COUNTER   = 1
      M_GAUGE     = 2
      M_SUMMARY   = 3
      M_HISTOGRAM = 4

      # Customised Bucket set to use for the Pooler clone times set to more appropriate intervals.
      POOLER_CLONE_TIME_BUCKETS = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 120.0, 180.0, 240.0, 300.0, 600.0].freeze
      POOLER_READY_TIME_BUCKETS = [30.0, 60.0, 120.0, 180.0, 240.0, 300.0, 500.0, 800.0, 1200.0, 1600.0].freeze
      # Same for redis connection times - this is the same as the current Prometheus Default.
      # https://github.com/prometheus/client_ruby/blob/master/lib/prometheus/client/histogram.rb#L14
      REDIS_CONNECT_BUCKETS = [1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 18.0, 23.0].freeze

      @p_metrics = {}
      @torun = []

      # rubocop:disable Lint/MissingSuper
      def initialize(logger, params = {})
        @prefix = params['prefix'] || 'vmpooler'
        @prometheus_prefix = params['prometheus_prefix'] || 'vmpooler'
        @prometheus_endpoint = params['prometheus_endpoint'] || '/prometheus'
        @logger = logger

        # Setup up prometheus registry and data structures
        @prometheus = Prometheus::Client.registry
      end
# rubocop:enable Lint/MissingSuper

=begin # rubocop:disable Style/BlockComments
      The Metrics table is used to register metrics and translate/interpret the incoming metrics.

      This table describes all of the prometheus metrics that are recognised by the application.
      The background documentation for defining metrics is at: https://prometheus.io/docs/introduction/
      In particular, the naming practices should be adhered to: https://prometheus.io/docs/practices/naming/
      The Ruby Client docs are also useful: https://github.com/prometheus/client_ruby

      The table here allows the currently used stats definitions to be translated correctly for Prometheus.
      The current format is of the form A.B.C, where the final fields may be actual values (e.g. poolname).
      Prometheus metrics cannot use the '.' as a character, so this is either translated into '_' or
      variable parameters are expressed as labels accompanying the metric.

      Sample statistics are:
          # Example showing hostnames (FQDN)
          migrate_from.pix-jj26-chassis1-2.ops.puppetlabs.net
          migrate_to.pix-jj26-chassis1-8.ops.puppetlabs.net

          # Example showing poolname as a parameter
          poolreset.invalid.centos-8-x86_64

          # Examples showing similar sub-typed checkout stats
          checkout.empty.centos-8-x86_64
          checkout.invalid.centos-8-x86_64
          checkout.invalid.unknown
          checkout.success.centos-8-x86_64

          # Stats without any final parameter.
          connect.fail
          connect.open
          delete.failed
          delete.success

          # Stats with multiple param_labels
          vmpooler_user.debian-8-x86_64-pixa4.john

        The metrics implementation here preserves the existing framework which will continue to support
        graphite and statsd (since vmpooler is used outside of puppet). Some rationalisation and renaming
        of the actual metrics was done to get a more usable model to fit within the prometheus framework.
        This particularly applies to the user stats collected once individual machines are terminated as
        this would have challenged prometheus' ability due to multiple (8) parameters being collected
        in a single measure (which has a very high cardinality).

        Prometheus requires all metrics to be pre-registered (which is the primary reason for this
        table) and also uses labels to differentiate the characteristics of the measurement. This
        is used throughout to capture information such as poolnames. So for example, this is a sample
        of the prometheus metrics generated for the "vmpooler_ready" measurement:

          # TYPE vmpooler_ready gauge
          # HELP vmpooler_ready vmpooler number of machines in ready State
          vmpooler_ready{vmpooler_instance="vmpooler",poolname="win-10-ent-x86_64-pixa4"} 2.0
          vmpooler_ready{vmpooler_instance="vmpooler",poolname="debian-8-x86_64-pixa4"} 2.0
          vmpooler_ready{vmpooler_instance="vmpooler",poolname="centos-8-x86_64-pixa4"} 2.0

        Prometheus supports the following metric types:
        (see https://prometheus.io/docs/concepts/metric_types/)

          Counter (increment):
            A counter is a cumulative metric that represents a single monotonically increasing counter whose
            value can only increase or be reset to zero on restart

          Gauge:
            A gauge is a metric that represents a single numerical value that can arbitrarily go up and down.

          Histogram:
            A histogram samples observations (usually things like request durations or response sizes) and
            counts them in configurable buckets. It also provides a sum of all observed values.
            This replaces the timer metric supported by statsd

          Summary :
            Summary provides a total count of observations and a sum of all observed values, it calculates
            configurable quantiles over a sliding time window.
            (Summary is not used in vmpooler)

        vmpooler_metrics_table is a table of hashes, where the hash key represents the first part of the
        metric name, e.g. for the metric 'delete.*' (see above) the key would be 'delete:'. "Sub-metrics",
        are supported, again for the 'delete.*' example, this can be subbed into '.failed' and '.success'

        The entries within the hash as are follows:

          mtype:
            Metric type, which is one of the following constants:
              M_COUNTER   = 1
              M_GAUGE     = 2
              M_SUMMARY   = 3
              M_HISTOGRAM = 4

          torun:
            Indicates which process the metric is for - within vmpooler this is either ':api' or ':manager'
            (there is a suggestion that we change this to two separate tables).

          docstring:
            Documentation string for the metric - this is displayed as HELP text by the endpoint.

          metric_suffixes:
            Array of sub-metrics of the form 'sub-metric: "doc-string for sub-metric"'. This supports
            the generation of individual sub-metrics for all elements in the array.

          param_labels:
            This is an optional array of symbols for the final labels in a metric. It should not be
            specified if there are no additional parameters.

            If it specified, it can either be a single symbol, or two or more symbols. The treatment
            differs if there is only one symbol given as all of the remainder of the metric string
            supplied is collected into a label with the symbol name. This allows the handling of
            node names (FQDN).

            To illustrate:
            1. In the 'connect.*' or 'delete.*' example above, it should not be specified.
            2. For the 'migrate_from.*' example above, the remainder of the measure is collected
               as the 'host_name' label.
            3. For the 'vmpooler_user' example above, the first parameter is treated as the pool
               name, and the second as the username.

=end
      def vmpooler_metrics_table
        {
          errors: {
            mtype: M_COUNTER,
            torun: %i[manager],
            docstring: 'Count of errors for pool',
            metric_suffixes: {
              markedasfailed: 'timeout waiting for instance to initialise',
              duplicatehostname: 'unable to create instance due to duplicate hostname',
              staledns: 'unable to create instance due to duplicate DNS record'
            },
            param_labels: %i[template_name]
          },
          user: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Number of pool instances and the operation performed by a user',
            param_labels: %i[user operation poolname]
          },
          usage_litmus: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Number of pool instances and the operation performed by Litmus jobs',
            param_labels: %i[user operation poolname]
          },
          usage_jenkins_instance: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Number of pool instances and the operation performed by Jenkins instances',
            param_labels: %i[jenkins_instance value_stream operation poolname]
          },
          usage_branch_project: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Number of pool instances and the operation performed by Litmus jobs by Jenkins branch/project',
            param_labels: %i[branch project operation poolname]
          },
          usage_job_component: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Number of pool instances and the operation performed by Litmus jobs Jenkins by job/component',
            param_labels: %i[job_name component_to_test operation poolname]
          },
          checkout: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Pool checkout counts',
            metric_suffixes: {
              nonresponsive: 'checkout failed - non responsive machine',
              empty: 'checkout failed - no machine',
              success: 'successful checkout',
              invalid: 'checkout failed - invalid template'
            },
            param_labels: %i[poolname]
          },
          delete: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Delete machine',
            metric_suffixes: {
              success: 'succeeded',
              failed: 'failed'
            },
            param_labels: []
          },
          ondemandrequest_generate: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Ondemand request',
            metric_suffixes: {
              duplicaterequests: 'failed duplicate request',
              success: 'succeeded'
            },
            param_labels: []
          },
          ondemandrequest_fail: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Ondemand request failure',
            metric_suffixes: {
              toomanyrequests: 'too many requests',
              invalid: 'invalid poolname'
            },
            param_labels: %i[poolname]
          },
          config: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'vmpooler pool configuration request',
            metric_suffixes: { invalid: 'Invalid' },
            param_labels: %i[poolname]
          },
          poolreset: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Pool reset counter',
            metric_suffixes: { invalid: 'Invalid Pool' },
            param_labels: %i[poolname]
          },
          connect: {
            mtype: M_COUNTER,
            torun: %i[manager],
            docstring: 'vmpooler connect (to vSphere)',
            metric_suffixes: {
              open: 'Connect Succeeded',
              fail: 'Connect Failed'
            },
            param_labels: []
          },
          migrate_from: {
            mtype: M_COUNTER,
            torun: %i[manager],
            docstring: 'vmpooler machine migrated from',
            param_labels: %i[host_name]
          },
          migrate_to: {
            mtype: M_COUNTER,
            torun: %i[manager],
            docstring: 'vmpooler machine migrated to',
            param_labels: %i[host_name]
          },
          http_requests_vm_total: {
            mtype: M_COUNTER,
            torun: %i[api],
            docstring: 'Total number of HTTP request/sub-operations handled by the Rack application under the /vm endpoint',
            param_labels: %i[method subpath operation]
          },
          ready: {
            mtype: M_GAUGE,
            torun: %i[manager],
            docstring: 'vmpooler number of machines in ready State',
            param_labels: %i[poolname]
          },
          running: {
            mtype: M_GAUGE,
            torun: %i[manager],
            docstring: 'vmpooler number of machines running',
            param_labels: %i[poolname]
          },
          connection_available: {
            mtype: M_GAUGE,
            torun: %i[manager],
            docstring: 'vmpooler redis connections available',
            param_labels: %i[type provider]
          },
          time_to_ready_state: {
            mtype: M_HISTOGRAM,
            torun: %i[manager],
            buckets: POOLER_READY_TIME_BUCKETS,
            docstring: 'Time taken for machine to read ready state for pool',
            param_labels: %i[poolname]
          },
          migrate: {
            mtype: M_HISTOGRAM,
            torun: %i[manager],
            buckets: POOLER_CLONE_TIME_BUCKETS,
            docstring: 'vmpooler time taken to migrate machine for pool',
            param_labels: %i[poolname]
          },
          clone: {
            mtype: M_HISTOGRAM,
            torun: %i[manager],
            buckets: POOLER_CLONE_TIME_BUCKETS,
            docstring: 'vmpooler time taken to clone machine',
            param_labels: %i[poolname]
          },
          destroy: {
            mtype: M_HISTOGRAM,
            torun: %i[manager],
            buckets: POOLER_CLONE_TIME_BUCKETS,
            docstring: 'vmpooler time taken to destroy machine',
            param_labels: %i[poolname]
          },
          connection_waited: {
            mtype: M_HISTOGRAM,
            torun: %i[manager],
            buckets: REDIS_CONNECT_BUCKETS,
            docstring: 'vmpooler redis connection wait time',
            param_labels: %i[type provider]
          }
        }
      end

      # Helper to add individual prom metric.
      # Allow Histograms to specify the bucket size.
      def add_prometheus_metric(metric_spec, name, docstring)
        case metric_spec[:mtype]
        when M_COUNTER
          metric_class = Prometheus::Client::Counter
        when M_GAUGE
          metric_class = Prometheus::Client::Gauge
        when M_SUMMARY
          metric_class = Prometheus::Client::Summary
        when M_HISTOGRAM
          metric_class = Prometheus::Client::Histogram
        else
          raise("Unable to register metric #{name} with metric type #{metric_spec[:mtype]}")
        end

        if (metric_spec[:mtype] == M_HISTOGRAM) && (metric_spec.key? :buckets)
          prom_metric = metric_class.new(
            name.to_sym,
            docstring: docstring,
            labels: metric_spec[:param_labels] + [:vmpooler_instance],
            buckets: metric_spec[:buckets],
            preset_labels: { vmpooler_instance: @prefix }
          )
        else
          prom_metric = metric_class.new(
            name.to_sym,
            docstring: docstring,
            labels: metric_spec[:param_labels] + [:vmpooler_instance],
            preset_labels: { vmpooler_instance: @prefix }
          )
        end
        @prometheus.register(prom_metric)
      end

      # Top level method to register all the prometheus metrics.

      def setup_prometheus_metrics(torun)
        @torun = torun
        @p_metrics = vmpooler_metrics_table
        @p_metrics.each do |name, metric_spec|
          # Only register metrics appropriate to api or manager
          next if (torun & metric_spec[:torun]).empty?

          if metric_spec.key? :metric_suffixes
            # Iterate thru the suffixes if provided to register multiple counters here.
            metric_spec[:metric_suffixes].each do |metric_suffix|
              add_prometheus_metric(
                metric_spec,
                "#{@prometheus_prefix}_#{name}_#{metric_suffix[0]}",
                "#{metric_spec[:docstring]} #{metric_suffix[1]}"
              )
            end
          else
            # No Additional counter suffixes so register this as metric.
            add_prometheus_metric(
              metric_spec,
              "#{@prometheus_prefix}_#{name}",
              metric_spec[:docstring]
            )
          end
        end
      end

      # locate a metric and check/interpet the sub-fields.
      def find_metric(label)
        sublabels = label.split('.')
        metric_key = sublabels.shift.to_sym
        raise("Invalid Metric #{metric_key} for #{label}") unless @p_metrics.key? metric_key

        metric_spec = @p_metrics[metric_key]
        raise("Invalid Component #{component} for #{metric_key}") if (metric_spec[:torun] & @torun).nil?

        metric = metric_spec.clone

        if metric.key? :metric_suffixes
          metric_subkey = sublabels.shift.to_sym
          raise("Invalid Metric #{metric_key}_#{metric_subkey} for #{label}") unless metric[:metric_suffixes].key? metric_subkey.to_sym

          metric[:metric_name] = "#{@prometheus_prefix}_#{metric_key}_#{metric_subkey}"
        else
          metric[:metric_name] = "#{@prometheus_prefix}_#{metric_key}"
        end

        # Check if we are looking for a parameter value at last element.
        if metric.key? :param_labels
          metric[:labels] = {}
          # Special case processing here - if there is only one parameter label then make sure
          # we append all of the remaining contents of the metric with "." separators to ensure
          # we get full nodenames (e.g. for Migration to node operations)
          if metric[:param_labels].length == 1
            metric[:labels][metric[:param_labels].first] = sublabels.join('.')
          else
            metric[:param_labels].reverse_each do |param_label|
              metric[:labels][param_label] = sublabels.pop(1).first
            end
          end
        end
        metric
      end

      # Helper to get lab metrics.
      def get(label)
        metric = find_metric(label)
        [metric, @prometheus.get(metric[:metric_name])]
      end

      # Note - Catch and log metrics failures so they can be noted, but don't interrupt vmpooler operation.
      def increment(label)
        begin
          counter_metric, c = get(label)
          c.increment(labels: counter_metric[:labels])
        rescue StandardError => e
          @logger.log('s', "[!] prometheus error logging metric #{label} increment : #{e}")
        end
      end

      def gauge(label, value)
        begin
          unless value.nil?
            gauge_metric, g = get(label)
            g.set(value.to_i, labels: gauge_metric[:labels])
          end
        rescue StandardError => e
          @logger.log('s', "[!] prometheus error logging gauge #{label}, value #{value}: #{e}")
        end
      end

      def timing(label, duration)
        begin
          # https://prometheus.io/docs/practices/histograms/
          unless duration.nil?
            histogram_metric, hm = get(label)
            hm.observe(duration.to_f, labels: histogram_metric[:labels])
          end
        rescue StandardError => e
          @logger.log('s', "[!] prometheus error logging timing event label #{label}, duration #{duration}: #{e}")
        end
      end
    end
  end
end
