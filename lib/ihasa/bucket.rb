require 'digest/sha1'
require 'ihasa/lua'
module Ihasa
  # Bucket class. That bucket fills up to burst, by rate per
  # second. Each accept? or accept?! call decrement it from 1.
  class Bucket
    attr_reader :redis
    def initialize(rate, burst, prefix, redis)
      @prefix = prefix
      @keys = Ihasa::OPTIONS.map { |opt| "#{prefix}:#{opt.upcase}" }
      @redis = redis
      @rate = Float rate
      @burst = Float burst
      self.class.digest = Digest::SHA1.hexdigest Lua::TOKEN_BUCKET_ALGORITHM
    end

    SETUP_ADVICE = 'Ensure that the method '\
    'Ihasa::Bucket#save was called.'.freeze
    SETUP_ERROR = ('Redis raised an error: %{msg}. ' + SETUP_ADVICE).freeze
    class RedisNamespaceSetupError < RuntimeError; end

    def accept?
      result = redis.evalsha(self.class.digest, @keys) == OK
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

    def save
      self.class.initialize_redis_namespace(@redis, @keys, @rate, @burst)
    end

    # deprecated
    def initialize_redis_namespace
      warn 'The Ihasa::Bucket#initialize_redis_namespace is deprecated. ' \
        'Use Ihasa::Bucket#save instead.'
      save
    end

    def delete
      @redis.del(@keys)
    end

    class << self
      attr_accessor :digest

      def create(*args)
        new(*args).tap(&:save)
      end

      def initialize_redis_namespace(redis, keys, rate_value, burst_value)
        sha = redis.script(:load, Lua::TOKEN_BUCKET_ALGORITHM)
        if sha != digest
          raise "SHA1 inconsistency: expected #{digest}, got #{sha}"
        end
        redis.eval(Lua.configuration(rate_value, burst_value), keys)
      end
    end
  end
end
