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
        ['example.com', 'example'],
        ['sub.example.com', 'sub'],
        ['adjective-noun.example.com', 'adjective-noun'],
        ['abc123.example.com', 'abc123']
    ].each do |hostname, expected|
      it { expect(subject.hostname_shorten(hostname)).to eq expected }
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
    let(:backend) { double('backend') }

    it 'adds up pools correctly' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:pipelined).with(no_args).and_return [1,1]

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 2, total: 10, percent: 20.0})
    end

    it 'handles 0 from redis' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 5}
      ]

      allow(redis).to receive(:pipelined).with(no_args).and_return [1,0]

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 10, percent: 10.0})
    end

    it 'handles 0 size' do
      pools = [
          {'name' => 'p1', 'size' => 5},
          {'name' => 'p2', 'size' => 0}
      ]

      allow(redis).to receive(:pipelined).with(no_args).and_return [1,0]

      expect(subject.get_capacity_metrics(pools, redis)).to eq({current: 1, total: 5, percent: 20.0})
    end

    it 'handles empty pool array' do
      allow(redis).to receive(:pipelined).with(no_args).and_return []
      expect(subject.get_capacity_metrics([], redis)).to eq({current: 0, total: 0, percent: 0})
    end
  end

  describe '#get_queue_metrics' do
    let(:redis) { double('redis') }

    it 'handles empty pool array' do
      allow(redis).to receive(:pipelined).with(no_args).and_return [0]
      allow(redis).to receive(:get).and_return 0

      expect(subject.get_queue_metrics([], redis)).to eq({requested: 0, pending: 0, cloning: 0, booting: 0, ready: 0, running: 0, completed: 0, total: 0})
    end

    it 'adds pool queues correctly' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      allow(redis).to receive(:pipelined).with(no_args).and_return [1,1]
      allow(redis).to receive(:get).and_return(1,0)

      expect(subject.get_queue_metrics(pools, redis)).to eq({requested: 6, pending: 2, cloning: 1, booting: 1, ready: 2, running: 2, completed: 2, total: 14})
    end

    it 'sets booting to 0 when negative calculation' do
      pools = [
          {'name' => 'p1'},
          {'name' => 'p2'}
      ]

      allow(redis).to receive(:pipelined).with(no_args).and_return [1,1]
      allow(redis).to receive(:get).and_return(5,0)

      expect(subject.get_queue_metrics(pools, redis)).to eq({requested: 6, pending: 2, cloning: 5, booting: 0, ready: 2, running: 2, completed: 2, total: 14})
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
      let(:default_encryption) do
        {
          :method => :start_tls,
          :tls_options => { :ssl_version => 'TLSv1' }
        }
      end

      context 'without a service account' do
        it 'should attempt ldap authentication' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when authentication is successful' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, nil).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when authentication fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, nil).and_return(false)

          expect(subject.authenticate(auth, username_str, password_str)).to be false
        end
      end

      context 'with a service account' do
        let(:service_account_hash) do
          {
            :user_dn => 'cn=Service Account,ou=users,dc=example,dc=com',
            :password => 's3cr3t'
          }
        end
        let(:auth) {
          {
            'provider' => 'ldap',
            ldap: {
              'host' => host,
              'base' => base,
              'user_object' => user_object,
              'service_account_hash' => service_account_hash
            }
          }
        }
        it 'should attempt ldap authentication' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, service_account_hash)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when authentication is successful' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, service_account_hash).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when authentication fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base, username_str, password_str, service_account_hash).and_return(false)

          expect(subject.authenticate(auth, username_str, password_str)).to be false
        end
      end

      context 'with an alternate ssl_version' do
        let(:secure_encryption) do
          {
            :method => :start_tls,
            :tls_options => { :ssl_version => 'TLSv1_2' }
          }
        end
        before(:each) do
          auth[:ldap]['encryption'] = secure_encryption
        end

        it 'should specify the alternate ssl_version when authenticating' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, secure_encryption, user_object, base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end
      end

      context 'with an alternate port' do
        let(:alternate_port) { 636 }
        before(:each) do
          auth[:ldap]['port'] = alternate_port
        end

        it 'should specify the alternate port when authenticating' do
          expect(subject).to receive(:authenticate_ldap).with(alternate_port, host, default_encryption, user_object, base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end
      end

      context 'with simple_tls and port 636' do
        let(:secure_port) { 636 }
        let(:secure_encryption) do
          {
            :method => :simple_tls,
            :tls_options => { :ssl_version => 'TLSv1_2' }
          }
        end
        before(:each) do
          auth[:ldap]['port'] = secure_port
          auth[:ldap]['encryption'] = secure_encryption
        end

        it 'should specify the secure port and encryption options when authenticating' do
          expect(subject).to receive(:authenticate_ldap).with(secure_port, host, secure_encryption, user_object, base, username_str, password_str, nil)

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
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[0], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should not search the second base when the first binds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[0], username_str, password_str, nil).and_return(true)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the second base when the first bind fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when any bind succeeds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[1], username_str, password_str, nil).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when all bind attempts fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object, base[1], username_str, password_str, nil).and_return(false)

          expect(subject.authenticate(auth, username_str, password_str)).to be false
        end
      end

      context 'with multiple search user objects' do
        let(:user_object) {
          [
            'uid',
            'cn'
          ]
        }
        before(:each) do
          auth[:ldap]['user_object'] = user_object
        end

        it 'should attempt to bind with each user object' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base, username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should not search the second user object when the first binds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base, username_str, password_str, nil).and_return(true)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the second user object when the first bind fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base, username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base, username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when any bind succeeds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base, username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base, username_str, password_str, nil).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when all bind attempts fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base, username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base, username_str, password_str, nil).and_return(false)

          expect(subject.authenticate(auth, username_str, password_str)).to be false
        end
      end

      context 'with multiple search user objects and with multiple search bases' do
        let(:user_object) {
          [
            'uid',
            'cn'
          ]
        }
        let(:base) {
          [
            'ou=user,dc=test,dc=com',
            'ou=service,ou=user,dc=test,dc=com'
          ]
        }
        before(:each) do
          auth[:ldap]['base'] = base
          auth[:ldap]['user_object'] = user_object
        end

        it 'should attempt to bind with each user object and base' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should not continue searching when the first combination binds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(true)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil)
          expect(subject).to_not receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the remaining combinations when the first bind fails' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the remaining combinations when the first two binds fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should search the remaining combination when the first three binds fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil)

          subject.authenticate(auth, username_str, password_str)
        end

        it 'should return true when any bind succeeds' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil).and_return(true)

          expect(subject.authenticate(auth, username_str, password_str)).to be true
        end

        it 'should return false when all bind attempts fail' do
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[0], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[0], base[1], username_str, password_str, nil).and_return(false)
          expect(subject).to receive(:authenticate_ldap).with(default_port, host, default_encryption, user_object[1], base[1], username_str, password_str, nil).and_return(false)

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
    let(:encryption) do
      {
        :method => :start_tls,
        :tls_options => { :ssl_version => 'TLSv1' }
      }
    end
    let(:service_account_hash) do
      {
        :user_dn => 'cn=Service Account,ou=users,dc=example,dc=com',
        :password => 's3cr3t'
      }
    end
    let(:ldap) { double('ldap') }
    it 'should create a new ldap connection' do
      allow(ldap).to receive(:bind)
      expect(Net::LDAP).to receive(:new).with(
        :host => host,
        :port => port,
        :encryption => encryption,
        :base => base,
        :auth => {
          :method => :simple,
          :username => "#{user_object}=#{username_str},#{base}",
          :password => password_str
        }
      ).and_return(ldap)

      subject.authenticate_ldap(port, host, encryption, user_object, base, username_str, password_str)
    end

    it 'should return true when a bind is successful' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind).and_return(true)

      expect(subject.authenticate_ldap(port, host, encryption, user_object, base, username_str, password_str)).to be true
    end

    it 'should return false when a bind fails' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind).and_return(false)

      expect(subject.authenticate_ldap(port, host, encryption, user_object, base, username_str, password_str)).to be false
    end

    it 'should return true when a bind_as is successful' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind_as).and_return(true)

      expect(subject.authenticate_ldap(port, host, encryption, user_object, base, username_str, password_str, service_account_hash)).to be true
    end

    it 'should return false when a bind_as fails' do
      expect(Net::LDAP).to receive(:new).and_return(ldap)
      expect(ldap).to receive(:bind_as).and_return(false)

      expect(subject.authenticate_ldap(port, host, encryption, user_object, base, username_str, password_str, service_account_hash)).to be false
    end
  end

end
