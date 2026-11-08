local used = tonumber(redis.call('GET', KEYS[1]) or '0')
if used > 0 then
  redis.call('DECR', KEYS[1])
end
return 0
