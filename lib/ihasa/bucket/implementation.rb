require 'ihasa/lua'
require 'singleton'
module Ihasa
  # For redis server whith version >= 3.2
  class Bucket::Implementation
    include Singleton

    def save(bucket)
      sha = bucket.redis.script(:load, Lua::TOKEN_BUCKET_ALGORITHM)
      if sha != Lua::TOKEN_BUCKET_HASH
        raise "SHA1 mismatch: expected #{Lua::TOKEN_BUCKET_HASH}, got #{sha}"
      end
      bucket.redis.eval(
        Lua.configuration(bucket.rate, bucket.burst),
        bucket.keys
      )
    end

    def accept?(bucket)
      bucket.redis.evalsha(Lua::TOKEN_BUCKET_HASH, bucket.keys)
    end
  end
end
