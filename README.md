No more pounding on your APIs !

Ihasa is a ruby implementation of the [token bucket algorithm](https://en.wikipedia.org/wiki/Token_bucket) backed-up by Redis.

It  provides a way to share your rate/burst limit across multiple servers, as well as a simple interface.

*Why use Ihasa?*

1. It's easy to use ([go check the usage section](#usage)
2. It supports rate AND burst
3. It does not reset all rate limit consumption each new second/minute/hour
4. It has [namespaces](#namespaces)


- [Installation](#installation)
- [Usage](#usage)
  - [Advanced](#advanced)
- [Example](#example)

## Installation

Installation is standard:

```
$ gem install ihasa
```

You can as well include it in you `Gemfile`:

```
gem 'ihasa', require: false
```

## Usage

Be sure to require Ihasa:

```ruby
require 'ihasa'
```

To create a new bucket accepting 5 requests per second with an allowed burst of 10
requests per second (the default values), use the `Ihasa.bucket` method:

```ruby
bucket = Ihasa.bucket
```

Please note that the default redis connection is built from the `REDIS_URL`
environment variable, or use the default constructor of redis-rb
(`redis://localhost:6379`).

Now, you can use your token bucket to check if an incoming request can be handled
or must be turned down:

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

Please note that there is also a `Ihasa::Bucket#accept?!` method that raise a
`Ihasa::Bucket::EmptyBucket` errors if the limit is violated.

### Advanced

Here is some details on the available configuration options of the Ihasa::Bucket
class.

#### Configuring rate and burst limit

Two configuration options exists to configure the rate and burst limits:

```ruby
bucket = Ihasa.bucket(rate: 20, burst: 100)
```

#### Namespaces

You can have as many bucket as you want on the same redis instance, as long as you
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

By default, all new buckets use the redis instance hosted at localhost:6379. There is
however two way to configure the used redis instance:

1. Override the `REDIS_URL` env variable. All new buckets will use that instance
2. Override the redis url on a bucket creation basis like follow:

```ruby
Ihasa.bucket(redis: Redis.new(url: 'redis://fancy_host:6379'))
```

## Example

This is an example of a rack middleware accepting 20 requests per seconds, and
tolerating burst up to 100 requests per second:

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
