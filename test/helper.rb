require 'rubygems'
require 'em-spec/test'
require 'em-http-request'
require 'socket'

if RUBY_VERSION < '1.9.0'
  gem 'test-unit'
  require 'test/unit'
  class TestCase < Test::Unit::TestCase
    include ::EM::Test
  end
else
  require 'minitest/unit'
  MiniTest::Unit.autorun
  class TestCase < MiniTest::Unit::TestCase
    include ::EM::Test
  end
end

class Hash
  def sanitize_keys
    reject do |key, value|
      [:timestamp, :issued].include?(key)
    end
  end
end

Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*.rb', &method(:require))
