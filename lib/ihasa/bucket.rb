require 'digest/sha1'
module Ihasa
  NOK = 0
  OK = 1
  # Bucket class. That bucket fills up to burst, by rate per
  # second. Each accept? or accept?! call decrement it from 1.
  class Bucket
    OPTS = %i(rate burst last allowance).freeze
    attr_reader :redis
    def initialize(rate, burst, prefix, redis)
      @prefix = prefix
      @keys = OPTS.each_with_object({}) do |opt, hash|
        hash[opt] = "#{prefix}:#{opt.upcase}"
      end
      @redis = redis
      @rate = Float rate
      @burst = Float burst
      self.class.digest = Digest::SHA1.hexdigest self.class.statement
    end

    SETUP_ADVICE = 'Ensure that the method '\
    'Ihasa::Bucket#initialize_redis_namespace was called.'.freeze
    SETUP_ERROR = ('Redis raised an error: %{msg}. ' + SETUP_ADVICE).freeze
    class RedisNamespaceSetupError < RuntimeError; end

    def accept?
      result = redis.evalsha(self.class.digest, @keys.values) == OK
      return yield if result && block_given?
      result
    rescue Redis::CommandError => e
      raise RedisNamespaceSetupError, SETUP_ERROR % { msg: e.message }
    end

    class EmptyBucket < RuntimeError; end

    def accept!
      result = (block_given? ? accept?(&Proc.new) : accept?)
      raise EmptyBucket, "Bucket #{@prefix} throttle limit" unless result
      result
    end

    def initialize_redis_namespace
      self.class.initialize_redis_namespace(@redis, @keys.values, @rate, @burst)
    end

    class << self
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

      attr_accessor :digest

      def initialize_redis_namespace(redis, keys, rate_value, burst_value)
        load_statement redis
        redis.eval(<<-LUA, keys)
          #{INTRO_STATEMENT}
          #{redis_set rate, rate_value}
          #{redis_set burst, burst_value}
          #{redis_set allowance, burst_value}
          #{redis_set last, 'now'}
        LUA
      end

      private

      # Please note that the replicate_commands is mandatory when using a
      # non deterministic command before writing shit to the redis instance.
      INTRO_STATEMENT = <<-LUA.freeze
        redis.replicate_commands()
        local now = redis.call('TIME')
        now = now[1] + now[2] * 10 ^ -6
      LUA

      def load_statement(redis)
        sha = redis.script(:load, statement)
        if sha != digest
          raise 'SHA1 inconsistency: expected #{digest}, got #{sha}'
        end
      end

      ELAPSED_STATEMENT = 'local elapsed = now - last'.freeze

      def local_statements
        results = OPTS.map do |key|
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

      def redis_exists(key)
        "redis.call('EXISTS', #{key})"
      end

      def index(key)
        OPTS.index(key) + 1
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
        super unless OPTS.include? sym
        redis_key sym
      end
    end
  end
end
