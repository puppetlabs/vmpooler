def redis
  unless @redis
    @redis = Redis.new
    @redis.select(15) # let's use the highest numbered database available in a default install
  end
  @redis
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

def create_ready_vm(template, name, token = nil)
  create_vm(name, token)
  redis.sadd("vmpooler__ready__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", "template", template)
end

def create_running_vm(template, name, token = nil)
  create_vm(name, token)
  redis.sadd("vmpooler__running__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", "template", template)
end

def create_pending_vm(template, name, token = nil)
  create_vm(name, token)
  redis.sadd("vmpooler__pending__#{template}", name)
  redis.hset("vmpooler__vm__#{name}", "template", template)
end

def create_vm(name, token = nil, redis_handle = nil)
  redis_db = redis_handle ? redis_handle : redis
  redis_db.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis_db.hset("vmpooler__vm__#{name}", 'token:token', token) if token
end

def create_migrating_vm(name, pool, redis_handle = nil)
  redis_db = redis_handle ? redis_handle : redis
  redis_db.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
  redis_db.sadd("vmpooler__migrating__#{pool}", name)
end

def add_vm_to_migration_set(name, redis_handle = nil)
  redis_db = redis_handle ? redis_handle : redis
  redis_db.sadd('vmpooler__migration', name)
end

def fetch_vm(vm)
  redis.hgetall("vmpooler__vm__#{vm}")
end

def snapshot_vm(vm, snapshot = '12345678901234567890123456789012')
  redis.sadd('vmpooler__tasks__snapshot', "#{vm}:#{snapshot}")
  redis.hset("vmpooler__vm__#{vm}", "snapshot:#{snapshot}", "1")
end

def has_vm_snapshot?(vm)
  redis.smembers('vmpooler__tasks__snapshot').any? do |snapshot|
    instance, sha = snapshot.split(':')
    vm == instance
  end
end

def vm_reverted_to_snapshot?(vm, snapshot = nil)
  redis.smembers('vmpooler__tasks__snapshot-revert').any? do |action|
    instance, sha = action.split(':')
    instance == vm and (snapshot ? (sha == snapshot) : true)
  end
end

def pool_has_ready_vm?(pool, vm)
  !!redis.sismember('vmpooler__ready__' + pool, vm)
end
