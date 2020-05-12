require 'mock_redis'

def redis
  unless @redis
    @redis = MockRedis.new
  end
  @redis
end

# Mock an object which represents a Logger.  This stops the proliferation
# of allow(logger).to .... expectations in tests.
class MockLogger
  def log(_level, string)
  end
end

def expect_json(ok = true, http = 200)
  expect(last_response.header['Content-Type']).to eq('application/json')

  if (ok == true) then
    expect(JSON.parse(last_response.body)['ok']).to eq(true)
  else
    expect(JSON.parse(last_response.body)['ok']).to eq(false)
  end

  expect(last_response.status).to eq(http)
end

def create_token(token, user, timestamp)
  redis.hset("vmpooler__token__#{token}", 'user', user)
  redis.hset("vmpooler__token__#{token}", 'created', timestamp)
end

def get_token_data(token)
  redis.hgetall("vmpooler__token__#{token}")
end

def token_exists?(token)
  result = get_token_data
  result && !result.empty?
end

def create_ready_vm(template, name, redis, token = nil)
  create_vm(name, redis, token)
  redis.sadd("vmpooler__ready__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", "template", template)
end

def create_running_vm(template, name, redis, token = nil, user = nil)
  create_vm(name, redis, token, user)
  redis.sadd("vmpooler__running__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", 'template', template)
  redis.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis.hset("vmpooler__vm__#{name}", 'host', 'host1')
end

def create_pending_vm(template, name, redis, token = nil)
  create_vm(name, redis, token)
  redis.sadd("vmpooler__pending__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", "template", template)
end

def create_vm(name, redis, token = nil, user = nil)
  redis.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis.hset("vmpooler__vm__#{name}", 'clone', Time.now)
  redis.hset("vmpooler__vm__#{name}", 'token:token', token) if token
  redis.hset("vmpooler__vm__#{name}", 'token:user', user) if user
end

def create_completed_vm(name, pool, redis, active = false)
  redis.sadd("vmpooler__completed__#{pool}", name)
  redis.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis.hset("vmpooler__active__#{pool}", name, Time.now) if active
end

def create_discovered_vm(name, pool, redis)
  redis.sadd("vmpooler__discovered__#{pool}", name)
end

def create_migrating_vm(name, pool, redis)
  redis.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis.sadd("vmpooler__migrating__#{pool}", name)
end

def create_tag(vm, tag_name, tag_value, redis)
  redis.hset("vmpooler__vm__#{vm}", "tag:#{tag_name}", tag_value)
end

def add_vm_to_migration_set(name, redis)
  redis.sadd('vmpooler__migration', name)
end

def fetch_vm(vm)
  redis.hgetall("vmpooler__vm__#{vm}")
end

def set_vm_data(vm, key, value, redis)
  redis.hset("vmpooler__vm__#{vm}", key, value)
end

def snapshot_revert_vm(vm, snapshot = '12345678901234567890123456789012', redis)
  redis.sadd('vmpooler__tasks__snapshot-revert', "#{vm}:#{snapshot}")
  redis.hset("vmpooler__vm__#{vm}", "snapshot:#{snapshot}", "1")
end

def snapshot_vm(vm, snapshot = '12345678901234567890123456789012', redis)
  redis.sadd('vmpooler__tasks__snapshot', "#{vm}:#{snapshot}")
  redis.hset("vmpooler__vm__#{vm}", "snapshot:#{snapshot}", "1")
end

def disk_task_vm(vm, disk_size = '10', redis)
  redis.sadd('vmpooler__tasks__disk', "#{vm}:#{disk_size}")
end

def has_vm_snapshot?(vm, redis)
  redis.smembers('vmpooler__tasks__snapshot').any? do |snapshot|
    instance, _sha = snapshot.split(':')
    vm == instance
  end
end

def vm_reverted_to_snapshot?(vm, redis, snapshot = nil)
  redis.smembers('vmpooler__tasks__snapshot-revert').any? do |action|
    instance, sha = action.split(':')
    instance == vm and (snapshot ? (sha == snapshot) : true)
  end
end

def pool_has_ready_vm?(pool, vm, redis)
  !!redis.sismember('vmpooler__ready__' + pool, vm)
end

def create_ondemand_request_for_test(request_id, score, platforms_string, redis, user = nil, token = nil)
  redis.zadd('vmpooler__provisioning__request', score, request_id)
  redis.hset("vmpooler__odrequest__#{request_id}", 'requested', platforms_string)
  redis.hset("vmpooler__odrequest__#{request_id}", 'token:token', token) if token
  redis.hset("vmpooler__odrequest__#{request_id}", 'token:user', user) if user
end

def set_ondemand_request_status(request_id, status, redis)
  redis.hset("vmpooler__odrequest__#{request_id}", 'status', status)
end

def create_ondemand_vm(vmname, request_id, pool, pool_alias, redis)
  redis.sadd("vmpooler__#{request_id}__#{pool_alias}__#{pool}", vmname)
end

def create_ondemand_creationtask(request_string, score, redis)
  redis.zadd('vmpooler__odcreate__task', score, request_string)
end

def create_ondemand_processing(request_id, score, redis)
  redis.zadd('vmpooler__provisioning__processing', score, request_id)
end
