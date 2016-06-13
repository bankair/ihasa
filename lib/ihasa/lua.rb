module Ihasa
  class Lua
    # Please note that the replicate_commands is mandatory when using a
    # non deterministic command before writing shit to the redis instance.
    NOW_DECLARATION = <<-LUA.freeze
      redis.replicate_commands()
      local now = redis.call('TIME')
      now = now[1] + now[2] * 10 ^ -6
    LUA

    ALLOWANCE_UPDATE_STATEMENT = <<-LUA.freeze
      allowance = allowance + (elapsed * rate)
      if allowance > burst then
        allowance = burst
      end
    LUA

    class << self
      def configuration(rate_value, burst_value)
        <<-LUA
          #{NOW_DECLARATION}
          #{redis_set rate, rate_value}
          #{redis_set burst, burst_value}
          #{redis_set allowance, burst_value}
          #{redis_set last, 'now'}
        LUA
      end

      def index(key)
        Bucket::OPTS.index(key) + 1
      end

      def redis_key(key)
        "KEYS[#{index key}]"
      end

      def redis_get(key)
        "tonumber(redis.call('GET', #{key}))"
      end

      def redis_set(key, value)
        "redis.call('SET', #{key}, tostring(#{value}))"
      end

      def redis_exists(key)
        "redis.call('EXISTS', #{key})"
      end

      def method_missing(sym, *args, &block)
        super unless Bucket::OPTS.include? sym
        redis_key sym
      end

      def to_local(key)
        "local #{key} = tonumber(#{redis_get(redis_key(key))})"
      end
    end
    ELAPSED_STATEMENT = 'local elapsed = now - last'.freeze
    SEP = "\n".freeze
    LOCAL_VARIABLES = Bucket::OPTS
                      .map { |key| to_local(key) }
                      .tap { |vars| vars << ELAPSED_STATEMENT }.join(SEP).freeze
    class << self
      def token_bucket_algorithm
        @algorithm ||= <<-LUA
          #{NOW_DECLARATION}
          #{LOCAL_VARIABLES}
          #{ALLOWANCE_UPDATE_STATEMENT}
          local result = #{Ihasa::NOK}
          if allowance >= 1.0 then
            allowance = allowance - 1.0
            result = #{Ihasa::OK}
          end
          #{redis_set(last, 'now')}
          #{redis_set(allowance, 'allowance')}
          return result
        LUA
      end
    end
  end
end
