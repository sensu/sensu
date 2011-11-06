require 'rubygems' if RUBY_VERSION < '1.9.0'
gem 'test-unit'
require "test/unit"
require 'em-spec/test'
Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*', &method(:require))
