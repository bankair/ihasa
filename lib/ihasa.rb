require 'redis'
require 'ihasa/version'
require 'ihasa/bucket'

module Ihasa
  module_function
  def default_redis
    @redis ||= if ENV['REDIS_URL']
                 Redis.new url: ENV['REDIS_URL']
               else
                 Redis.new
               end
  end

  DEFAULT_REDIS_PREFIX = 'IHAB'
  def bucket(rate: 5, burst: 10, prefix: DEFAULT_REDIS_PREFIX, redis: default_redis)
    @implementation = Bucket.new(rate, burst, prefix, redis)
  end
end
