local attempts = redis.call('INCR', KEYS[1])
if attempts == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return { attempts, redis.call('TTL', KEYS[1]) }
