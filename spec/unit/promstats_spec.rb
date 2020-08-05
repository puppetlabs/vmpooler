# frozen_string_literal: true

require 'spec_helper'

describe 'prometheus' do
  logger = MockLogger.new
  params = { 'prefix' => 'test', 'prometheus_prefix'  => 'mtest', 'prometheus_endpoint'  => 'eptest' }
  subject = Vmpooler::Metrics::Promstats.new(logger, params)
  let(:logger) { MockLogger.new }

  describe '#initialise' do
    it 'returns a Metrics object' do
      expect(Vmpooler::Metrics::Promstats.new(logger)).to be_a(Vmpooler::Metrics)
    end
  end

  describe '#find_metric' do
    context "Single Value Parameters" do
      let!(:foo_metrics) do
        { metric_suffixes: { bar: 'baz' },
          param_labels: %i[first second last] }
      end
      let!(:labels_hash) { { labels: { :first => nil, :second => nil, :last => nil } } }
      before { subject.instance_variable_set(:@p_metrics, { foo: foo_metrics }) }
  
      it 'returns the metric for a given label including parsed labels' do
        expect(subject.find_metric('foo.bar')).to include(metric_name: 'mtest_foo_bar')
        expect(subject.find_metric('foo.bar')).to include(foo_metrics)
        expect(subject.find_metric('foo.bar')).to include(labels_hash)
      end

      it 'raises an error when the given label is not present in metrics' do
        expect { subject.find_metric('bogus') }.to raise_error(RuntimeError, 'Invalid Metric bogus for bogus')
      end
  
      it 'raises an error when the given label specifies metric_suffixes but the following suffix not present in metrics' do
        expect { subject.find_metric('foo.metric_suffixes.bogus') }.to raise_error(RuntimeError, 'Invalid Metric foo_metric_suffixes for foo.metric_suffixes.bogus')
      end
    end

    context "Node Name Handling" do
      let!(:node_metrics) do
        { metric_name: 'connection_to',
          param_labels: %i[node] }
      end
      let!(:nodename_hash) { { labels: { :node => 'test.bar.net'}}}
      before { subject.instance_variable_set(:@p_metrics, { connection_to: node_metrics }) }

      it 'Return final remaining fields (e.g. fqdn) in last label' do
        expect(subject.find_metric('connection_to.test.bar.net')).to include(nodename_hash)
      end
    end
  end

  context 'setup_prometheus_metrics' do
    before(:all) do
      Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
      subject.setup_prometheus_metrics(%i[api manager])
    end

    describe '#setup_prometheus_metrics' do
      it 'calls add_prometheus_metric for each item in list' do
        Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
        expect(subject).to receive(:add_prometheus_metric).at_least(subject.vmpooler_metrics_table.size).times
        subject.setup_prometheus_metrics(%i[api manager])
      end
    end

    describe '#increment' do
      it 'Increments checkout.nonresponsive.#{template_backend}' do
        template_backend = 'test'
        expect { subject.increment("checkout.nonresponsive.#{template_backend}") }.to change {
          metric, po = subject.get("checkout.nonresponsive.#{template_backend}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments checkout.empty. + requested' do
        requested = 'test'
        expect { subject.increment('checkout.empty.' + requested) }.to change {
          metric, po = subject.get('checkout.empty.' + requested)
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments checkout.success. + vmtemplate' do
        vmtemplate = 'test-template'
        expect { subject.increment('checkout.success.' + vmtemplate) }.to change {
          metric, po = subject.get('checkout.success.' + vmtemplate)
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments checkout.invalid. + bad_template' do
        bad_template = 'test-template'
        expect { subject.increment('checkout.invalid.' + bad_template) }.to change {
          metric, po = subject.get('checkout.invalid.' + bad_template)
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments checkout.invalid.unknown' do
        expect { subject.increment('checkout.invalid.unknown') }.to change {
          metric, po = subject.get('checkout.invalid.unknown')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments delete.failed' do
        bad_template = 'test-template'
        expect { subject.increment('delete.failed') }.to change {
          metric, po = subject.get('delete.failed')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments delete.success' do
        bad_template = 'test-template'
        expect { subject.increment('delete.success') }.to change {
          metric, po = subject.get('delete.success')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments ondemandrequest_generate.duplicaterequests' do
        bad_template = 'test-template'
        expect { subject.increment('ondemandrequest_generate.duplicaterequests') }.to change {
          metric, po = subject.get('ondemandrequest_generate.duplicaterequests')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments ondemandrequest_generate.success' do
        bad_template = 'test-template'
        expect { subject.increment('ondemandrequest_generate.success') }.to change {
          metric, po = subject.get('ondemandrequest_generate.success')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments ondemandrequest_fail.toomanyrequests.#{bad_template}' do
        bad_template = 'test-template'
        expect { subject.increment("ondemandrequest_fail.toomanyrequests.#{bad_template}") }.to change {
          metric, po = subject.get("ondemandrequest_fail.toomanyrequests.#{bad_template}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments ondemandrequest_fail.invalid.#{bad_template}' do
        bad_template = 'test-template'
        expect { subject.increment("ondemandrequest_fail.invalid.#{bad_template}") }.to change {
          metric, po = subject.get("ondemandrequest_fail.invalid.#{bad_template}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments config.invalid.#{bad_template}' do
        bad_template = 'test-template'
        expect { subject.increment("config.invalid.#{bad_template}") }.to change {
          metric, po = subject.get("config.invalid.#{bad_template}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments config.invalid.unknown' do
        expect { subject.increment('config.invalid.unknown') }.to change {
          metric, po = subject.get('config.invalid.unknown')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments poolreset.invalid.#{bad_pool}' do
        bad_pool = 'test-pool'
        expect { subject.increment("poolreset.invalid.#{bad_pool}") }.to change {
          metric, po = subject.get("poolreset.invalid.#{bad_pool}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments poolreset.invalid.unknown' do
        expect { subject.increment('poolreset.invalid.unknown') }.to change {
          metric, po = subject.get('poolreset.invalid.unknown')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments errors.markedasfailed.#{pool}' do
        pool = 'test-pool'
        expect { subject.increment("errors.markedasfailed.#{pool}") }.to change {
          metric, po = subject.get("errors.markedasfailed.#{pool}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments errors.duplicatehostname.#{pool_name}' do
        pool_name = 'test-pool'
        expect { subject.increment("errors.duplicatehostname.#{pool_name}") }.to change {
          metric, po = subject.get("errors.duplicatehostname.#{pool_name}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments errors.staledns.#{pool_name}' do
        pool_name = 'test-pool'
        expect { subject.increment("errors.staledns.#{pool_name}") }.to change {
          metric, po = subject.get("errors.staledns.#{pool_name}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments user.#{user}.#{poolname}' do
        user = 'myuser'
        poolname = 'test-pool'
        expect { subject.increment("user.#{user}.#{poolname}") }.to change {
          metric, po = subject.get("user.#{user}.#{poolname}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments usage_litmus.#{user}.#{poolname}' do
        user = 'myuser'
        poolname = 'test-pool'
        expect { subject.increment("usage_litmus.#{user}.#{poolname}") }.to change {
          metric, po = subject.get("usage_litmus.#{user}.#{poolname}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments label usage_jenkins_instance.#{jenkins_instance}.#{value_stream}.#{poolname}' do
        jenkins_instance = 'jenkins_test_instance'
        value_stream = 'notional_value'
        poolname = 'test-pool'
        expect { subject.increment("usage_jenkins_instance.#{jenkins_instance}.#{value_stream}.#{poolname}") }.to change {
          metric, po = subject.get("usage_jenkins_instance.#{jenkins_instance}.#{value_stream}.#{poolname}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments label usage_branch_project.#{branch}.#{project}.#{poolname}' do
        branch = 'treetop'
        project = 'test-project'
        poolname = 'test-pool'
        expect { subject.increment("usage_branch_project.#{branch}.#{project}.#{poolname}") }.to change {
          metric, po = subject.get("usage_branch_project.#{branch}.#{project}.#{poolname}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments label usage_job_component.#{job_name}.#{component_to_test}.#{poolname}' do
        job_name = 'a-job'
        component_to_test = 'component-name'
        poolname = 'test-pool'
        expect { subject.increment("usage_job_component.#{job_name}.#{component_to_test}.#{poolname}") }.to change {
          metric, po = subject.get("usage_job_component.#{job_name}.#{component_to_test}.#{poolname}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments connect.open' do
        expect { subject.increment('connect.open') }.to change {
          metric, po = subject.get('connect.open')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments connect.fail' do
        expect { subject.increment('connect.fail') }.to change {
          metric, po = subject.get('connect.fail')
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments migrate_from.#{vm_hash[\'host_name\']}' do
        vm_hash = { 'host_name': 'testhost.testdomain' }
        expect { subject.increment("migrate_from.#{vm_hash['host_name']}") }.to change {
          metric, po = subject.get("migrate_from.#{vm_hash['host_name']}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments "migrate_to.#{dest_host_name}"' do
        dest_host_name = 'testhost.testdomain'
        expect { subject.increment("migrate_to.#{dest_host_name}") }.to change {
          metric, po = subject.get("migrate_to.#{dest_host_name}")
          po.get(labels: metric[:labels])
        }.by(1)
      end
      it 'Increments label http_requests_vm_total.#{method}.#{subpath}.#{operation}' do
        method = 'get'
        subpath = 'template'
        operation = 'something'
        expect { subject.increment("http_requests_vm_total.#{method}.#{subpath}.#{operation}") }.to change {
          metric, po = subject.get("http_requests_vm_total.#{method}.#{subpath}.#{operation}")
          po.get(labels: metric[:labels])
        }.by(1)
      end

    end

    describe '#gauge' do
      # metrics.gauge("ready.#{pool_name}", $redis.scard("vmpooler__ready__#{pool_name}"))
      it 'sets value of ready.#{pool_name} to $redis.scard("vmpooler__ready__#{pool_name}"))' do
        # is there a specific redis value that should be tested?
        pool_name = 'test-pool'
        test_value = 42
        expect { subject.gauge("ready.#{pool_name}", test_value) }.to change {
          metric, po = subject.get("ready.#{pool_name}")
          po.get(labels: metric[:labels])
        }.from(0).to(42)
      end
      # metrics.gauge("running.#{pool_name}", $redis.scard("vmpooler__running__#{pool_name}"))
      it 'sets value of running.#{pool_name} to $redis.scard("vmpooler__running__#{pool_name}"))' do
        # is there a specific redis value that should be tested?
        pool_name = 'test-pool'
        test_value = 42
        expect { subject.gauge("running.#{pool_name}", test_value) }.to change {
          metric, po = subject.get("running.#{pool_name}")
          po.get(labels: metric[:labels])
        }.from(0).to(42)
      end
    end

    describe '#timing' do
      it 'sets histogram value of time_to_ready_state.#{pool} to finish' do
        pool = 'test-pool'
        finish = 42
        expect { subject.timing("time_to_ready_state.#{pool}", finish) }.to change {
          metric, po = subject.get("time_to_ready_state.#{pool}")
          po.get(labels: metric[:labels])
        }
      end
      it 'sets histogram value of clone.#{pool} to finish' do
        pool = 'test-pool'
        finish = 42
        expect { subject.timing("clone.#{pool}", finish) }.to change {
          metric, po = subject.get("clone.#{pool}")
          po.get(labels: metric[:labels])
        }
      end
      it 'sets histogram value of migrate.#{pool} to finish' do
        pool = 'test-pool'
        finish = 42
        expect { subject.timing("migrate.#{pool}", finish) }.to change {
          metric, po = subject.get("migrate.#{pool}")
          po.get(labels: metric[:labels])
        }
      end
      it 'sets histogram value of destroy.#{pool} to finish' do
        pool = 'test-pool'
        finish = 42
        expect { subject.timing("destroy.#{pool}", finish) }.to change {
          metric, po = subject.get("destroy.#{pool}")
          po.get(labels: metric[:labels])
        }
      end
    end
  end
end
