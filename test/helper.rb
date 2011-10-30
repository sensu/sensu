require 'rubygems' if RUBY_VERSION < '1.9.0'
gem 'minitest'
require 'minitest/autorun'
require 'minitest/pride'
require 'em-ventually'
require 'rest_client'
Dir.glob(File.dirname(__FILE__) + '/../lib/sensu/*', &method(:require))

api = Process.fork do
  Sensu::API.run(:config_file => File.join(File.dirname(__FILE__), 'config.json'))
end

MiniTest::Unit.after_tests do
  Process.kill('KILL', api)
end
