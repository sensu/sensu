require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'amqp'
require 'json'

#
# Read the CM created JSON config file
#
config_file = if ENV['dev']
  File.dirname(__FILE__) + '/../../config.json'
else
  '/etc/sa-monitoring/config.json'
end

CONFIG = JSON.parse(File.open(config_file, 'r').read)
