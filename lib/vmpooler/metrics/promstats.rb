# frozen_string_literal: true

module Vmpooler
  class Promstats < Metrics
    attr_reader :prefix, :endpoint, :metrics_prefix

    # Constants for Metric Types
    M_COUNTER   = 1
    M_GAUGE     = 2
    M_SUMMARY   = 3
    M_HISTOGRAM = 4

    # Customised Bucket set to use for the Pooler clone times set to more appropriate intervals.
    POOLER_TIME_BUCKETS = [1.0, 2.5, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0].freeze
    # Same for Redis connection times - this is the same as the current Prometheus Default.
    # https://github.com/prometheus/client_ruby/blob/master/lib/prometheus/client/histogram.rb#L14
    REDIS_CONNECT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

    @p_metrics = {}

    def initialize(params = {})
      @prefix = params['prefix'] || 'vmpooler'
      @metrics_prefix = params['metrics_prefix'] || 'vmpooler'
      @endpoint = params['endpoint'] || '/prometheus'

      # Hmm - think this is breaking the logger .....
      @logger = params.delete('logger') || Logger.new(STDOUT)

      # Setup up prometheus registry and data structures
      @prometheus = Prometheus::Client.registry
    end

    # Metrics structure used to register the metrics and also translate/interpret the incoming metrics.
    def vmpooler_metrics_table
      {
        errors: {
          mtype: M_COUNTER,
          docstring: 'Count of Errors for pool',
          prom_metric_prefix: "#{@metrics_prefix}_errors",
          metric_suffixes: {
            markedasfailed: 'Timeout waiting for instance to initialise',
            duplicatehostname: 'Unable to create instance due to duplicate hostname'
          },
          param_labels: %i[template_name]
        },
        usage: {
          mtype: M_COUNTER,
          docstring: 'Number of Pool Instances of this created',
          prom_metric_prefix: "#{@metrics_prefix}_usage",
          param_labels: %i[user poolname]
        },
        user: {
          # This metrics is leads to a lot of label values which is likely to challenge data storage
          # on prometheus - see Best Practices: https://prometheus.io/docs/practices/naming/#labels
          # So it is likely that this metric may need to be simplified or broken into a number
          # of smaller metrics to capture the detail without challenging prometheus
          mtype: M_COUNTER,
          docstring: 'vmpooler user counters',
          prom_metric_prefix: "#{@metrics_prefix}_user",
          param_labels: %i[user instancex value_stream branch project job_name component_to_test poolname]
        },
        checkout: {
          mtype: M_COUNTER,
          docstring: 'Pool Checkout counts',
          prom_metric_prefix: "#{@metrics_prefix}_checkout",
          metric_suffixes: {
            nonresponsive: 'Checkout Failed - Non Responsive Machine',
            empty: 'Checkout Failed - no machine',
            success: 'Successful Checkout',
            invalid: 'Checkout Failed - Invalid Template'
          },
          param_labels: %i[poolname]
        },
        config: {
          mtype: M_COUNTER,
          docstring: 'vmpooler Pool Configuration Request',
          prom_metric_prefix: "#{@metrics_prefix}_config",
          metric_suffixes: { invalid: 'Invalid' },
          param_labels: %i[poolname]
        },
        poolreset: {
          mtype: M_COUNTER,
          docstring: 'Pool Reset Counter',
          prom_metric_prefix: "#{@metrics_prefix}_poolreset",
          metric_suffixes: { invalid: 'Invalid Pool' },
          param_labels: %i[poolname]
        },
        connect: {
          mtype: M_COUNTER,
          docstring: 'vmpooler Connect (to vSphere)',
          prom_metric_prefix: "#{@metrics_prefix}_connect",
          metric_suffixes: {
            open: 'Connect Succeeded',
            fail: 'Connect Failed'
          },
          param_labels: []
        },
        migrate_from: {
          mtype: M_COUNTER,
          docstring: 'vmpooler Machine Migrated from',
          prom_metric_prefix: "#{@metrics_prefix}_migrate_from",
          param_labels: %i[host_name]
        },
        migrate_to: {
          mtype: M_COUNTER,
          docstring: 'vmpooler Machine Migrated to',
          prom_metric_prefix: "#{@metrics_prefix}_migrate_to",
          param_labels: %i[host_name]
        },
        ready: {
          mtype: M_GAUGE,
          docstring: 'vmpooler Number of Machines in Ready State',
          prom_metric_prefix: "#{@metrics_prefix}_ready",
          param_labels: %i[poolname]
        },
        running: {
          mtype: M_GAUGE,
          docstring: 'vmpooler Number of Machines Running',
          prom_metric_prefix: "#{@metrics_prefix}_running",
          param_labels: %i[poolname]
        },
        connection_available: {
          mtype: M_GAUGE,
          docstring: 'vmpooler Redis Connections Available',
          prom_metric_prefix: "#{@metrics_prefix}_connection_available",
          param_labels: %i[type provider]
        },
        time_to_ready_state: {
          mtype: M_HISTOGRAM,
          buckets: POOLER_TIME_BUCKETS,
          docstring: 'Time taken for machine to read ready state for pool',
          prom_metric_prefix: "#{@metrics_prefix}_time_to_ready_state",
          param_labels: %i[poolname]
        },
        migrate: {
          mtype: M_HISTOGRAM,
          buckets: POOLER_TIME_BUCKETS,
          docstring: 'vmpooler Time taken to migrate machine for pool',
          prom_metric_prefix: "#{@metrics_prefix}_migrate",
          param_labels: %i[poolname]
        },
        clone: {
          mtype: M_HISTOGRAM,
          buckets: POOLER_TIME_BUCKETS,
          docstring: 'vmpooler Time taken to Clone Machine',
          prom_metric_prefix: "#{@metrics_prefix}_clone",
          param_labels: %i[poolname]
        },
        destroy: {
          mtype: M_HISTOGRAM,
          buckets: POOLER_TIME_BUCKETS,
          docstring: 'vmpooler Time taken to Destroy Machine',
          prom_metric_prefix: "#{@metrics_prefix}_destroy",
          param_labels: %i[poolname]
        },
        connection_waited: {
          mtype: M_HISTOGRAM,
          buckets: REDIS_CONNECT_BUCKETS,
          docstring: 'vmpooler Redis Connection Wait Time',
          prom_metric_prefix: "#{@metrics_prefix}_connection_waited",
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

    def setup_prometheus_metrics
      @p_metrics = vmpooler_metrics_table
      @p_metrics.each do |_name, metric_spec|
        if metric_spec.key? :metric_suffixes
          # Iterate thru the suffixes if provided to register multiple counters here.
          metric_spec[:metric_suffixes].each do |metric_suffix|
            add_prometheus_metric(
              metric_spec,
              "#{metric_spec[:prom_metric_prefix]}_#{metric_suffix[0]}",
              "#{metric_spec[:docstring]} #{metric_suffix[1]}"
            )
          end
        else
          # No Additional counter suffixes so register this as metric.
          add_prometheus_metric(
            metric_spec,
            metric_spec[:prom_metric_prefix],
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

      metric = @p_metrics[metric_key].clone

      if metric.key? :metric_suffixes
        metric_subkey = sublabels.shift.to_sym
        raise("Invalid Metric #{metric_key}_#{metric_subkey} for #{label}") unless metric[:metric_suffixes].key? metric_subkey.to_sym

        metric[:metric_name] = "#{metric[:prom_metric_prefix]}_#{metric_subkey}"
      else
        metric[:metric_name] = metric[:prom_metric_prefix]
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
