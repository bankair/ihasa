# encoding: utf-8

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'ihasa/version'

Gem::Specification.new do |s|
  s.name = 'ihasa'
  s.version = Ihasa::Version::STRING
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.0.0'
  s.authors = ['Alexandre Ignjatovic']
  s.description = <<-EOF
    A Redis-backed rate limiter written in ruby and
    using the token bucket algorithm.
    Its light and efficient implementation takes
    advantage of the Lua capabilities of Redis.
  EOF

  s.email = 'alexandre.ignjatovic@gmail.com'
  s.files = `git ls-files`.split($RS).reject do |file|
    file =~ %r{^(?:
    spec/.*
    |Gemfile
    |Rakefile
    |\.rspec
    |\.gitignore
    |\.rubocop.yml
    |\.rubocop_todo.yml
    |.*\.eps
    )$}x
  end
  s.test_files = []
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.extra_rdoc_files = ['LICENSE.txt', 'README.md']
  s.homepage = 'http://github.com/bankair/ihasa'
  s.licenses = ['MIT']
  s.require_paths = ['lib']
  s.rubygems_version = '1.8.23'

  s.summary = 'Redis-backed rate limiter (token bucket) written in Ruby and Lua'

  s.add_runtime_dependency('redis', '~> 3')
  s.add_development_dependency('rspec', '~> 3.4')
end
