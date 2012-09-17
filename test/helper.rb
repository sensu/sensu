require 'rubygems'
require 'em-spec/test'
require 'em-http-request'

module TestUtil
  def sanitize_keys(hash)
    hash.reject do |key, value|
      [:timestamp, :issued].include?(key)
    end
  end

  def create_config_snippet(name, content)
    File.open(File.join(File.dirname(__FILE__), 'conf.d', name + '.tmp.json'), 'w') do |file|
      file.write((content.is_a?(Hash) ? content.to_json : content))
    end
  end

  def teardown
    Dir.glob('/tmp/sensu_*').each do |file|
      File.delete(file)
    end
    Dir.glob(File.dirname(__FILE__) + '/conf.d/*.tmp.json').each do |file|
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

Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*.rb', &method(:require))
