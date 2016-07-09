# Ihasa

[![Build Status](https://travis-ci.org/bankair/ihasa.svg?branch=master)](https://travis-ci.org/bankair/ihasa) [![Code Climate](https://codeclimate.com/github/bankair/ihasa/badges/gpa.svg)](https://codeclimate.com/github/bankair/ihasa)

_No more pounding on your APIs !_

Ihasa is a ruby implementation of the [token bucket algorithm](https://en.wikipedia.org/wiki/Token_bucket) backed-up by Redis.

It  provides a way to share your rate/burst limit across multiple servers, as well as a simple interface.

**Why use Ihasa?**

1. It's easy to use ([go check the usage section](#usage))
2. It supports rate AND burst
3. It does not reset all rate limit consumption each new second/minute/hour
4. It has [namespaces](#namespaces)

This README file contains the following sections:

- [Installation](#installation)
- [Usage](#usage)
  - [Advanced](#advanced)
- [Example](#example)

## Installation

Installation is standard:

```
$ gem install ihasa
```

You can include it in your `Gemfile` as well:

```
gem 'ihasa', require: false
```

## Usage

Be sure to require Ihasa:

```ruby
require 'ihasa'
```

To create a new bucket that accepts 5 requests per second with an allowed burst of 10
requests per second (the default values), use the `Ihasa.bucket` method:

```ruby
bucket = Ihasa.bucket
```

Please note that the default redis connection is built from the `REDIS_URL`
environment variable, or use the default constructor of redis-rb
(`redis://localhost:6379`).

Now, you can use your token bucket to check if an incoming request can be handled,
or must be declined:

```ruby
def process(request)
  if @bucket.accept?
    # Do very interesting things with the request
    # ...
  else
    puts "Could not process request #{request}. Rate limit violated."
  end
end
```

Please note that there is also a `Ihasa::Bucket#accept?!` method that raises an
`Ihasa::Bucket::EmptyBucket` error if the limit has already been reached.

### Advanced

In this section, you will find some details on the available configuration options of the Ihasa::Bucket
class, as well as advice on how to run many Buckets simultaneously.

#### Using multiple buckets

If you want to enforce per-customer rate limits, you must create as many buckets as you have customers.
Which can be quite a few if you are successful ;).

To have many buckets in parallel, and to avoid resetting your redis namespaces too often, I suggest you
no longer use the `Ihasa.bucket` method. Instead, you should back up your buckets with activerecord models
(for example) and initialize them in an after-creation model callback.

To help you with that, we added the `save` and `delete` instance methods to the `Ihasa::Bucket` class.

Example:

```ruby
  class Bucket < ActiveRecord::Base
    attr_accessible :rate, :burst, :prefix

    def implementation
      @implementation ||= Ihasa::Bucket.new(rate, burst, prefix, $redis)
    end

    # The Ihasa::Bucket#save set the relevant
    # keys in your redis instance to have a working bucket. Do it
    # only when you create or update your bucket's configuration.
    after_save { implementation.save }

    # The Ihasa::Bucket#delete remove the variables stored into
    # the redis instance.
    after_destroy { implementation.delete }

    delegate :accept?, to: :implementation
  end

  # Usage:

  Bucket.create(rate: 10, burst: 50, prefix: 'CustomerIdentifier42')

  # ...

  # Later, in a controller:
  DEFAULT_BUCKET = Ihasa.bucket(rate: 5, burst: 20, prefix: 'default')

  def process_request
    bucket = Bucket.find_by_prefix(params[:customer_identifier])
    unless bucket
      Rails.logger.warn("No bucket for customer #{params[:customer_identifier]}.")
      Rails.logger.warn('Using default config.')
      bucket = DEFAULT_BUCKET
    end
    unless bucket.accept?
      Rails.logger.error("Customer #{params[:customer_identifier]} violated its rate limit.")
      return head 403
    end
    # other actions not executed if rate limit violated
    # ...
  end
```

#### Configuring rate limit and burst limit

You can configure both the rate limit and burst limit:

```ruby
bucket = Ihasa.bucket(rate: 20, burst: 100)
```

#### Namespaces

You can have as many buckets as you want on the same redis instance, as long as you
configure different namespace for each of them.

Here is an example of using two different buckets for reading and writing to data:

```ruby
class Controller < ActionController::Base
  def self.read_bucket
    @read_bucket ||= Ihasa.bucket(prefix: 'read')
  end

  def self.write_bucket
    @write_bucket ||= Ihasa.bucket(prefix: 'write')
  end

  def read(request)
    return head 403 unless self.class.read_bucket.accept?
    # ... Standard rendering ...
  end

  def write(request)
    return head 403 unless self.class.write_bucket.accept?
    # ... Standard rendering ...
  end
```

#### Redis

By default, all new buckets use the redis instance hosted at localhost:6379. You can
override this default like so:

1. Override the `REDIS_URL` env variable. All new buckets will use that instance
2. Override the redis url on a bucket creation basis like this:

```ruby
Ihasa.bucket(redis: Redis.new(url: 'redis://fancy_host:6379'))
```

## Example

This is an example of a rack middleware that accepts 20 requests per seconds, and
allows bursts up to 100 requests per second:

```ruby
class RateLimiter
  BUCKET = Ihasa.bucket(rate: 20, burst: 100)

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if BUCKET.accept?
    [403, {'Content-Type' => 'text/plain'}, ["Request limit violated\n"]]
  end
end
```
