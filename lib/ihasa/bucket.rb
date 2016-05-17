module Ihasa
  NOK = 0
  OK = 1
  # Bucket class. That bucket fills up to burst, by rate per
  # second. Each accept? or accept?! call decrement it from 1.
  class Bucket
    attr_reader :redis
    def initialize(rate, burst, prefix, redis)
      @prefix = prefix
      @keys = {}
      @keys[:rate] = "#{prefix}:RATE"
      @keys[:allowance] = "#{prefix}:ALLOWANCE"
      @keys[:burst] = "#{prefix}:BURST"
      @keys[:last] = "#{prefix}:LAST"
      @redis = redis
      @rate = Float rate
      @burst = Float burst
      initialize_redis_namespace
    end

    def accept?
      result = redis_eval(statement) == OK
      return yield if result && block_given?
      result
    end

    class EmptyBucket < RuntimeError; end

    def accept!
      result = (block_given? ? accept?(&Proc.new) : accept?)
      raise EmptyBucket, "Bucket #{@prefix} throttle limit" unless result
      result
    end

    protected

    def initialize_redis_namespace
      redis_eval <<-LUA
        #{INTRO_STATEMENT}
        #{redis_set rate, @rate}
        #{redis_set burst, @burst}
        #{redis_set allowance, @burst}
        #{redis_set last, 'now'}
      LUA
    end

    require 'forwardable'
    extend Forwardable

    def_delegator :@keys, :keys
    def_delegator :@keys, :values, :redis_keys

    def index(key)
      keys.index(key) + 1
    end

    # Please note that the replicate_commands is mandatory when using a
    # non deterministic command before writing shit to the redis instance.
    INTRO_STATEMENT = <<-LUA.freeze
      redis.replicate_commands()
      local now = redis.call('TIME')
      now = now[1] + now[2] * 10 ^ -6
    LUA

    def redis_eval(statement)
      redis.eval(statement, redis_keys)
    end

    ELAPSED_STATEMENT = 'local elapsed = now - last'.freeze

    def local_statements
      results = %i(rate burst last allowance).map do |key|
        "local #{key} = tonumber(#{redis_get(redis_key(key))})"
      end
      results << ELAPSED_STATEMENT
      results.join "\n"
    end

    ALLOWANCE_UPDATE_STATEMENT = <<-LUA.freeze
      allowance = allowance + (elapsed * rate)
      if allowance > burst then
        allowance = burst
      end
    LUA

    def statement
      @statement ||= <<-LUA
        #{INTRO_STATEMENT}
        #{local_statements}
        #{ALLOWANCE_UPDATE_STATEMENT}
        local result = #{NOK}
        if allowance >= 1.0 then
          allowance = allowance - 1.0
          result = #{OK}
        end
        #{redis_set(last, 'now')}
        #{redis_set(allowance, 'allowance')}
        return result
      LUA
    end

    def redis_exists(key)
      "redis.call('EXISTS', #{key})"
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

    def method_missing(sym, *args, &block)
      super unless @keys.key?(sym)
      redis_key sym
    end
  end
end
