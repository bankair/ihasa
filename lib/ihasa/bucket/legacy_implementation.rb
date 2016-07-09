require 'ihasa/lua'
require 'singleton'
module Ihasa
  # For redis server whose version is prior to 3.2
  class Bucket::LegacyImplementation
    include Singleton

    def save(bucket)
      bucket.redis.eval(
        Lua.configuration(
          bucket.rate,
          bucket.burst,
          Lua.now_declaration(redis_time(bucket.redis))
        ),
        bucket.keys
      )
    end

    def accept?(bucket)
      now = redis_time bucket.redis
      script = Lua.token_bucket_algorithm_legacy(now)
      bucket.redis.eval(script, bucket.keys)
    end

    private

    MICROSECS_PER_SEC = 10**6
    def redis_time(redis)
      seconds, microseconds = redis.time
      seconds + microseconds.to_f / MICROSECS_PER_SEC
    end
  end
end
