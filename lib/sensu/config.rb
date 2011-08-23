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

config = JSON.parse(File.open(config_file, 'r').read)

#
# Substitute tokens in check commands with their matching client attribute
#
config['checks'].each_key do |name|
  config['checks'][name]['command'].gsub!(/:::(.*?):::/) { config['client'][$1.to_s].to_s }
end

#
# Create a tmp directory
#
begin
  Dir.mkdir('/tmp/sensu')
rescue SystemCallError
end

#
# Set the config constant
#
CONFIG = config
