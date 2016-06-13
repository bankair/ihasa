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
      self.class.digest = Digest::SHA1.hexdigest Lua.token_bucket_algorithm
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
      require 'ihasa/lua'

      attr_accessor :digest

      def initialize_redis_namespace(redis, keys, rate_value, burst_value)
        load_statement redis
        redis.eval(Lua::configuration(rate_value, burst_value), keys)
      end

      private

      def load_statement(redis)
        sha = redis.script(:load, Lua.token_bucket_algorithm)
        if sha != digest
          raise 'SHA1 inconsistency: expected #{digest}, got #{sha}'
        end
      end
    end
  end
end
