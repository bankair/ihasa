require 'redis'
class Ihasa
  DEBUG = true
  class Bucket
    attr_reader :redis # FIXME: remove after debug
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
      redis_init
    end

    def redis_init
      redis_eval <<-LUA
        #{INTRO_STATEMENT}
        #{redis_set rate, @rate}
        #{redis_set burst, @burst}
        #{redis_set allowance, @burst}
        #{redis_set last, 'now'}
      LUA
    end

    def guard
      result = redis_eval(statement) == OK
      if result && block_given?
        yield
      end
      result
    end

    class EmptyBucket < RuntimeError; end

    def guard!
      result = (block_given? ? guard(&Proc.new) : guard)
      raise EmptyBucket, "Bucket #{@prefix} throttle limit" unless result
      result
    end
    
    # FIXME: uncomment
    # protected

    require 'forwardable'
    extend Forwardable


    def_delegator :@keys, :keys
    def_delegator :@keys, :values, :redis_keys

    def index(key)
      keys.index(key) + 1
    end



    # Please note that the replicate_commands is mandatory when using a
    # non deterministic command before writing shit to the redis instance.
    INTRO_STATEMENT = <<-LUA
      redis.replicate_commands()
      local now = redis.call('TIME')
      now = now[1] + now[2] * 10 ^ -6
    LUA

    if DEBUG
      def redis_eval(statement)
        # warn "KEYS: #{redis_keys.inspect}"
        # warn "SCRIPT:"
        # statement.split("\n").each_with_index { |x, i| warn "#{i + 1} #{x}" }
        result = redis.eval(statement, redis_keys)
        if result
          warn "RESULT: #{result.first}"
          warn "ENV: #{result[1..-1].inspect}"
        end
        result
      end
    else
      def redis_eval(statement)
        redis.eval(statement, redis_keys)
      end
    end

    NOK = 0
    OK = 1

    if DEBUG
      def ok
        encapsulate OK
      end
      def nok
        encapsulate NOK
      end
    else
      def ok
        OK
      end
      def nok
        NOK
      end
    end

    def encapsulate(value)
      results = %w(allowance elapsed last now).map do |e|
        "'#{e}:' .. tostring(#{e})"
      end
      results.unshift value
      "{#{results.join(';')}}"
    end

    def elapsed_statement
      "local elapsed = now - last"
    end

    def local_statements
      results = %i(rate burst last allowance)
      results.map! { |key| "local #{key} = tonumber(#{redis_get(redis_key key)})" }
      results << elapsed_statement
      results.join "\n"
    end

    def statement
      return <<-LUA
      #{INTRO_STATEMENT}
      local trace = ''
      #{local_statements}
      trace = trace .. 'oldallow:' .. tostring(allowance) .. ';'
      trace = trace .. 'regen:' .. tostring(elapsed / rate) .. ';'
      allowance = allowance + (elapsed * rate)
      if allowance > burst then
        allowance = burst
      end
      #{redis_set(last, 'now')}
      if allowance < 1.0 then
        #{redis_set(allowance, 'allowance')}
        return #{nok}
      else
        allowance = allowance - 1.0
        #{redis_set(allowance, 'allowance')}
        return #{ok}
      end
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

  DEFAULT_REDIS_PREFIX = 'IHAB'

  class << self
    def default_redis
      @redis ||= Redis.new url: 'redis://192.168.99.100:32768' # FIXME: update after debug
    end

    def bucket(rate: 5, burst: 10, prefix: DEFAULT_REDIS_PREFIX, redis: default_redis)
      @implementation = Bucket.new(rate, burst, prefix, redis)
    end
  end
end

$b = Ihasa.bucket
loop { puts $b.guard; sleep 1}
