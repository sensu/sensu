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
    end

    def create_working_directory
      begin
        Dir.mkdir('/tmp/sensu')
      rescue SystemCallError
      end
    end
  end
end
