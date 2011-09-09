require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'
require 'uuidtools'
require 'amqp'
require 'em/syslog'
require File.join(File.dirname(__FILE__), 'helpers')

module Sensu
  class Config
    attr_accessor :settings

    def initialize(options={})
      config_file = options[:config_file] || '/etc/sensu/config.json'
      @settings = JSON.parse(File.open(config_file, 'r').read)
      validate_config
    end

    def validate_config
      @settings['checks'].each do |name, info|
        unless info['interval'].is_a?(Integer) && info['interval'] > 0
          raise 'configuration invalid, missing interval for check ' + name
        end
        unless info['command'].is_a?(String)
          raise 'configuration invalid, missing command for check ' + name
        end
        unless info['subscribers'].is_a?(Array) && info['subscribers'].count > 0
          raise 'configuration invalid, missing subscribers for check ' + name
        end
      end
    end

    def create_working_directory
      begin
        Dir.mkdir('/tmp/sensu')
      rescue SystemCallError
      end
    end

    def purge_working_directory
      Dir.foreach('/tmp/sensu') do |file|
        next if file == '.' || file == '..'
        File.delete('/tmp/sensu/' + file)
      end
    end
  end
end
