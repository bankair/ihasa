require 'digest/sha1'
module Ihasa
  # Contains lua related logic
  module Lua
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
      def now_declaration(value)
        "local now = #{value}"
      end

      # Please note that the replicate_commands is mandatory when using a
      # non deterministic command before writing shit to the redis instance
      # for versions >= 3.2
      def configuration(rate_value, burst_value, now_declaration = NOW_DECLARATION)
        <<-LUA
          #{now_declaration}
          #{set rate, rate_value}
          #{set burst, burst_value}
          #{set allowance, burst_value}
          #{set last, 'now'}
        LUA
      end

      def index(key)
        Integer(Ihasa::OPTIONS.index(key)) + 1
      end

      def fetch(key)
        "KEYS[#{index key}]"
      end

      def get(key)
        "tonumber(redis.call('GET', #{key}))"
      end

      def set(key, value)
        "redis.call('SET', #{key}, tostring(#{value}))"
      end

      def exists?(key)
        "redis.call('EXISTS', #{key})"
      end

      def method_missing(sym, *args, &block)
        super unless Ihasa::OPTIONS.include? sym
        fetch sym
      end

      def to_local(key)
        "local #{key} = tonumber(#{get(fetch(key))})"
      end
      
      def token_bucket_algorithm_legacy(now_value)
        <<-LUA.freeze
          #{now_declaration(now_value)}
          #{TOKEN_BUCKET_ALGORITHM_BODY}
        LUA
      end
    end

    ELAPSED_STATEMENT = 'local elapsed = now - last'.freeze
    SEP = "\n".freeze
    LOCAL_VARIABLES = Ihasa::OPTIONS
                      .map { |key| to_local(key) }
                      .tap { |vars| vars << ELAPSED_STATEMENT }.join(SEP).freeze
    TOKEN_BUCKET_ALGORITHM_BODY = <<-LUA.freeze
      #{LOCAL_VARIABLES}
      #{ALLOWANCE_UPDATE_STATEMENT}
      local result = #{Ihasa::NOK}
      if allowance >= 1.0 then
        allowance = allowance - 1.0
        result = #{Ihasa::OK}
      end
      #{set(last, 'now')}
      #{set(allowance, 'allowance')}
      return result
    LUA
    TOKEN_BUCKET_ALGORITHM = <<-LUA.freeze
      #{NOW_DECLARATION}
      #{TOKEN_BUCKET_ALGORITHM_BODY}
    LUA
    TOKEN_BUCKET_HASH = Digest::SHA1.hexdigest(
      Lua::TOKEN_BUCKET_ALGORITHM
    ).freeze

  end
end
