require 'spec_helper'
require 'net/ldap'

# A class for testing purposes that includes the Helpers.
# this is impersonating V1's `helpers do include Helpers end`
#
# This is the subject used throughout the test file.
#
class TestHelpers
  include Vmpooler::API::Helpers
end

describe Vmpooler::API::Helpers do

  subject { TestHelpers.new }

  describe '#hostname_shorten' do
    [
        ['example.com', 'not-example.com', 'example.com'],
        ['example.com', 'example.com', 'example.com'],
        ['sub.example.com', 'example.com', 'sub'],
        ['example.com', nil, 'example.com']
    ].each do |hostname, domain, expected|
      it { expect(subject.hostname_shorten(hostname, domain)).to eq expected }
    end
  end

  describe '#validate_date_str' do
    [
        ['2015-01-01', true],
        [nil, false],
        [false, false],
        [true, false],
        ['01-01-2015', false],
        ['1/1/2015', false]
    ].each do |date, expected|
      it { expect(subject.validate_date_str(date)).to eq expected }
    end
  end

  describe '#mean' do
    [
        [[1, 2, 3, 4], 2.5],
        [[1], 1],
        [[nil], 0],
        [[], 0]
    ].each do |list, expected|
      it "returns #{expected.inspect} for #{list.inspect}" do
        expect(subject.mean(list)).to eq expected
      end
    end
  end

  describe '#get_task_times' do
    let(:redis) { double('redis') }
    [
        ['task1', '2014-01-01', [1, 2, 3, 4], [1.0, 2.0, 3.0, 4.0]],
        ['task1', 'some date', [], []],
        ['task1', 'date', [2.2], [2.2]],
        ['task1', 'date', [2.2, 3, 3.0], [2.2, 3.0, 3.0]]
    ].each do |task, date, time_list, expected|
      it "returns #{expected.inspect} for task #{task.inspect}@#{date.inspect}" do
        allow(redis).to receive(:hvals).and_return time_list
        expect(subject.get_task_times(redis, task, date)).to eq expected
      end
    end
  end

  describe '#get_capacity_metrics' do
    let(:redis) { double('redis') }

    it 'adds up pools correctly' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 1

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 2, total: 10, percent: 20.0})
    end

    it 'handles 0 from redis' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 0

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 10, percent: 10.0})
    end

    it 'handles 0 size' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 0}
      ]

      allow(redis).to receive(:scard).with('vmpooler__ready__p1').and_return 1
      allow(redis).to receive(:scard).with('vmpooler__ready__p2').and_return 0

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 5, percent: 20.0})
    end

    it 'handles empty pool array' do
      expect(subject.get_capacity_metrics([], redis)).to eq({current: 0, total: 0, percent: 0})
    end
  end

  describe '#get_queue_metrics' do
    let(:redis) { double('redis') }

    it 'handles empty pool array' do
      allow(redis).to receive(:scard).and_return 0
      allow(redis).to receive(:get).and_return 0

      expect(subject.get_queue_metrics([], redis)).to eq({pending: 0, cloning: 0, booting: 0, ready: 0, running: 0, completed: 0, total: 0})
    end

    it 'adds pool queues correctly' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      pools.each do |p|
        %w(pending ready running completed).each do |action|
          allow(redis).to receive(:scard).with('vmpooler__' + action + '__' + p['name']).and_return 1
        end
      end
      allow(redis).to receive(:get).and_return 1

      expect(subject.get_queue_metrics(pools, redis)).to eq({pending: 2, cloning: 1, booting: 1, ready: 2, running: 2, completed: 2, total: 8})
    end

    it 'sets booting to 0 when negative calculation' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      pools.each do |p|
        %w(pending ready running completed).each do |action|
          allow(redis).to receive(:scard).with('vmpooler__' + action + '__' + p['name']).and_return 1
        end
      end
      allow(redis).to receive(:get).and_return 5

      expect(subject.get_queue_metrics(pools, redis)).to eq({pending: 2, cloning: 5, booting: 0, ready: 2, running: 2, completed: 2, total: 8})
    end
  end

  describe '#get_tag_metrics' do
    let(:redis) { double('redis') }

    it 'returns basic tag metrics' do
      allow(redis).to receive(:hgetall).with('vmpooler__tag__2015-01-01').and_return({"abcdefghijklmno:tag" => "value"})

      expect(subject.get_tag_metrics(redis, '2015-01-01')).to eq({"tag" => {"value"=>1, "total"=>1}})
    end

    it 'calculates tag totals' do
      allow(redis).to receive(:hgetall).with('vmpooler__tag__2015-01-01').and_return({"abcdefghijklmno:tag" => "value", "pqrstuvwxyz12345:tag" => "another_value"})

      expect(subject.get_tag_metrics(redis, '2015-01-01')).to eq({"tag"=>{"value"=>1, "total"=>2, "another_value"=>1}})
    end
  end

  describe '#pool_index' do
    let(:pools) {
      [
        {
          'name' => 'pool1'
        },
        {
          'name' => 'pool2'
        }
      ]
    }

    it 'should return a hash' do
      pools_hash = subject.pool_index(pools)

      expect(pools_hash).to be_a(Hash)
    end

    it 'should return the correct index for each pool' do
      pools_hash = subject.pool_index(pools)

      expect(pools[pools_hash['pool1']]['name']).to eq('pool1')
      expect(pools[pools_hash['pool2']]['name']).to eq('pool2')
    end
  end

  describe '#template_ready?' do
    let(:redis) { double('redis') }
    let(:template) { 'template/test1' }
    let(:poolname) { 'pool1' }
    let(:pool) {
      {
        'name' => poolname,
        'template' => template
      }
    }

    it 'returns false when there is no prepared template' do
      expect(redis).to receive(:hget).with('vmpooler__template__prepared', poolname).and_return(nil)

      expect(subject.template_ready?(pool, redis)).to be false
    end

    it 'returns true when configured and prepared templates match' do
      expect(redis).to receive(:hget).with('vmpooler__template__prepared', poolname).and_return(template)

      expect(subject.template_ready?(pool, redis)).to be true
    end

    it 'returns false when configured and prepared templates do not match' do
      expect(redis).to receive(:hget).with('vmpooler__template__prepared', poolname).and_return('template3')

      expect(subject.template_ready?(pool, redis)).to be false
    end
  end

  describe '#is_integer?' do
    it 'returns true when input is an integer' do
      expect(subject.is_integer? 4).to be true
    end

    it 'returns true when input is a string containing an integer' do
      expect(subject.is_integer? '4').to be true
    end

    it 'returns false when input is a string containing word characters' do
      expect(subject.is_integer? 'four').to be false
    end
  end

  describe '#authenticate' do
    let(:username_str) { 'admin' }
    let(:password_str) { 's3cr3t' }

    context 'with dummy provider' do
      let(:auth) {
        {
          'provider': 'dummy'
        }
      }
      it 'should return true' do
        expect(subject).to receive(:authenticate).with(auth, username_str, password_str).and_return(true)

        subject.authenticate(auth, username_str, password_str)
      end
    end

    context 'with ldap provider' do
      let(:host) { 'ldap.example.com' }
      let(:base) { 'ou=user,dc=test,dc=com' }
      let(:user_object) { 'uid' }
      let(:auth) {
        {
          'provider' => 'ldap',
          ldap: {
            'host' => host,
            'base' => base,
            'user_object' => user_object
          }
        }
      }
      let(:default_port) { 389 }
      it 'should attempt ldap authentication' do
        expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base, username_str, password_str)

        subject.authenticate(auth, username_str, password_str)
      end

      it 'should return true when authentication is successful' do
        expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base, username_str, password_str).and_return(true)

        expect(subject.authenticate(auth, username_str, password_str)).to be true
      end

      it 'should return false when authentication fails' do
        expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base, username_str, password_str).and_return(false)

        expect(subject.authenticate(auth, username_str, password_str)).to be false
      end

      context 'with an alternate port' do
        let(:alternate_port) { 636 }
        before(:each) do
          auth[:ldap]['port'] = alternate_port
        end

        it 'should specify the alternate port when authenticating' do
          expect(subject).to receive(:authenticate_ldap).with(alternate_port, host, user_object, base, username_str, password_str)

          subject.authenticate(auth, username_str, password_str)
        end
      end

      context 'with multiple search bases' do
        let(:base) {
          [
            'ou=user,dc=test,dc=com',
            'ou=service,ou=user,dc=test,dc=com'
          ]
        }
        before(:each) do
          auth[:ldap]['base'] = base
        end

        it 'should attempt to bind with each base' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[0], username_str, password_str)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[1], username_str, password_str)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should not search the second base when the first binds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[0], username_str, password_str).and_return(true)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, user_object, base[1], username_str, password_str)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the second base when the first bind fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[0], username_str, password_str).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[1], username_str, password_str)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when any bind succeeds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[0], username_str, password_str).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[1], username_str, password_str).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when all bind attempts fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[0], username_str, password_str).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, user_object, base[1], username_str, password_str).and_return(false)

          expect(subject.authenticate(auth, username_str, password_str)).to be false
        end
      end

    end

    context 'with unknown provider' do
      let(:auth) {
        {
          'provider': 'mystery'
        }
      }
      it 'should return false' do
        expect(subject).to receive(:authenticate).with(auth, username_str, password_str).and_return(false)
        subject.authenticate(auth, username_str, password_str)
      end
    end
  end

  describe '#authenticate_ldap' do
    let(:port) { 389 }
    let(:host) { 'ldap.example.com' }
    let(:user_object) { 'uid' }
    let(:base) { 'ou=users,dc=example,dc=com' }
    let(:username_str) { 'admin' }
    let(:password_str) { 's3cr3t' }
    let(:ldap) { double('ldap') }
    it 'should create a new ldap connection' do
      allow(ldap).to receive(:bind)
      expect(Net::LDAP).to receive(:new).with(
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
      ).and_return(ldap)

      subject.authenticate_ldap(port, host, user_object, base, username_str, password_str)
    end

    it 'should return true when a bind is successful' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind).and_return(true)

      expect(subject.authenticate_ldap(port, host, user_object, base, username_str, password_str)).to be true
    end

    it 'should return false when a bind fails' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind).and_return(false)

      expect(subject.authenticate_ldap(port, host, user_object, base, username_str, password_str)).to be false
    end
  end

end
