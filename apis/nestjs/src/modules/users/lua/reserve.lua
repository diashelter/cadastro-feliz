local used = tonumber(redis.call('GET', KEYS[1]) or '0')
if used >= tonumber(ARGV[1]) then
  return { 0, math.max(1, redis.call('TTL', KEYS[1])) }
end
used = redis.call('INCR', KEYS[1])
if used == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[2])
end
return { 1, math.max(1, redis.call('TTL', KEYS[1])) }
