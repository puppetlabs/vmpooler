def redis
  @redis ||= Redis.new
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

def create_ready_vm(template, name)
  redis.sadd('vmpooler__ready__' + template, name)
end

def create_vm(name)
  redis.hset("vmpooler__vm__#{name}", 'checkout', Time.now)
end

def fetch_vm(vm)
  redis.hgetall("vmpooler__vm__#{vm}")
end
