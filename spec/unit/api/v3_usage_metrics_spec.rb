# frozen_string_literal: true

require 'spec_helper'
require 'vmpooler/api/v3'

describe Vmpooler::API::V3 do
  let(:v3) { described_class.new! }
  let(:metrics) { double('metrics', increment: nil) }
  let(:vm) { 'vm1' }

  before do
    allow(v3).to receive(:backend).and_return(redis)
    allow(v3).to receive(:metrics).and_return(metrics)
    redis.hset("vmpooler__vm__#{vm}", 'template', 'pool.one')
  end

  describe '#component_to_test' do
    it 'gives nothing when there are no labels' do
      expect(v3.component_to_test('RMM', nil)).to be_nil
    end

    it 'gives the value of the label that matches' do
      expect(v3.component_to_test('B', 'A=1,B=2,C=3')).to eq('2')
    end

    it 'gives "none" when no label matches' do
      expect(v3.component_to_test('Z', 'A=1,B=2')).to eq('none')
    end

    it 'skips labels without a value' do
      expect(v3.component_to_test('B', 'A,B=2')).to eq('2')
      expect(v3.component_to_test('A', 'A,B=2')).to eq('none')
    end
  end

  describe '#update_user_metrics' do
    it 'counts an unauthenticated user, with the dots of the pool name replaced' do
      v3.update_user_metrics('create', vm)

      expect(metrics).to have_received(:increment).with('user.unauthenticated.create.pool_one')
    end

    it 'counts the user the token belongs to, with dots replaced' do
      redis.hset("vmpooler__vm__#{vm}", 'token:user', 'j.doe')

      v3.update_user_metrics('delete', vm)

      expect(metrics).to have_received(:increment).with('user.j_doe.delete.pool_one')
    end

    it 'counts a Litmus job on its own' do
      redis.hset("vmpooler__vm__#{vm}", 'token:user', 'jdoe')
      redis.hset("vmpooler__vm__#{vm}", 'tag:jenkins_build_url', 'https://jenkins.example/job/litmus_module/5/')

      v3.update_user_metrics('create', vm)

      expect(metrics).to have_received(:increment).with('usage_litmus.jdoe.create.pool_one')
      expect(metrics).not_to have_received(:increment).with(/usage_jenkins_instance/)
    end

    it 'counts a Jenkins job by instance, value stream, branch, project and component' do
      url = 'https://jenkins-enterprise.delivery.puppetlabs.net/job/' \
            'enterprise_pe-acceptance-tests_integration-system_pe_full_nightly_main/' \
            'LAYOUT=a,RMM_COMPONENT_TO_TEST_NAME=puppet/12/'
      redis.hset("vmpooler__vm__#{vm}", 'token:user', 'jdoe')
      redis.hset("vmpooler__vm__#{vm}", 'tag:jenkins_build_url', url)

      v3.update_user_metrics('create', vm)

      expect(metrics).to have_received(:increment)
        .with('usage_jenkins_instance.jenkins-enterprise_delivery_puppetlabs_net.enterprise.create.pool_one')
      expect(metrics).to have_received(:increment).with('usage_branch_project.main.pe-acceptance-tests.create.pool_one')
      expect(metrics).to have_received(:increment)
        .with('usage_job_component.integration-system_pe_full_nightly.puppet.create.pool_one')
    end

    it 'says so, and carries on, when the build URL is not what it expected' do
      redis.hset("vmpooler__vm__#{vm}", 'tag:jenkins_build_url', 'https://jenkins.example/job')

      expect { v3.update_user_metrics('create', vm) }.to output(/failed while evaluating usage labels on 'vm1'/).to_stdout
      expect(metrics).to have_received(:increment).with('user.unauthenticated.create.pool_one')
    end
  end

  describe 'the status cache' do
    let(:cache) { described_class.class_variable_get(:@@status_cache) }
    let(:now) { Time.at(1_700_000_000) }

    before do
      described_class.clear_status_cache
      allow(Time).to receive(:now) { now }
    end

    it 'gives back what was cached' do
      v3.set_cached_status('pools', ok: true)

      expect(v3.get_cached_status('pools')).to eq(ok: true)
    end

    it 'gives nothing for a key it does not have' do
      expect(v3.get_cached_status('missing')).to be_nil
    end

    it 'gives nothing once the entry is older than the cache lifetime' do
      v3.set_cached_status('pools', ok: true)
      allow(Time).to receive(:now).and_return(now + described_class::STATUS_CACHE_TTL + 1)

      expect(v3.get_cached_status('pools')).to be_nil
    end

    it 'keeps at most 10 entries, dropping the oldest' do
      11.times do |n|
        allow(Time).to receive(:now).and_return(now + n)
        v3.set_cached_status("view#{n}", n: n)
      end

      expect(cache.size).to eq(10)
      expect(cache).not_to have_key('view0')
      expect(cache).to have_key('view10')
    end
  end
end
