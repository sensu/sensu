if RUBY_VERSION < '1.9.0'
  require 'rubygems'
  gem 'test-unit'
end
require "test/unit"
require 'em-spec/test'
Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*', &method(:require))
