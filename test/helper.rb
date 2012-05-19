require 'rubygems'
require 'em-spec/test'
require 'em-http-request'
require 'socket'

module TestUtil
  def teardown
    Dir.glob('/tmp/sensu_*').each do |file|
      File.delete(file)
    end
  end
end

if RUBY_VERSION < '1.9.0'
  gem 'test-unit'

  require 'test/unit'

  class TestCase < Test::Unit::TestCase
    include ::EM::Test
    include TestUtil
  end
else
  require 'minitest/unit'

  MiniTest::Unit.autorun

  class TestCase < MiniTest::Unit::TestCase
    include ::EM::Test
    include TestUtil
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
