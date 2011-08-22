require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'
require 'uuidtools'
require 'amqp'
require 'em/syslog'
require 'sensu/helpers'

#
# Read the CM created JSON config file
#
config_file = if ENV['test']
  File.dirname(__FILE__) + '/../../config.json'
else
  '/etc/sensu/config.json'
end

CONFIG = JSON.parse(File.open(config_file, 'r').read)

#
# Create a tmp directory
#
begin
  Dir.mkdir('/tmp/sensu')
rescue SystemCallError
end
