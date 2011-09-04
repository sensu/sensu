require File.join(File.dirname(__FILE__), 'config')

config_file = if ENV['test']
  File.join(File.dirname(__FILE__), '/../../config.json')
else
  '/etc/sensu/config.json'
end

config = Sensu::Config.new(:config_file => config_file)
config.create_working_directory
CONFIG = config.settings
