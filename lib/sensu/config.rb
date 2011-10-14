require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'optparse'
require 'json'
require 'hashie'
require 'uuidtools'
require 'amqp'
require 'em/syslog'
require File.join(File.dirname(__FILE__), 'helpers')

module Sensu
  class Config
    attr_accessor :settings

    def initialize(options={})
      config_file = options[:config_file] || '/etc/sensu/config.json'
      @settings = Hashie::Mash.new(JSON.parse(File.open(config_file, 'r').read))
      validate_config
    end

    def validate_config
      @settings.checks.each do |name, details|
        unless details.interval.is_a?(Integer) && details.interval > 0
          raise 'configuration invalid, missing interval for check ' + name
        end
        unless details.command.is_a?(String)
          raise 'configuration invalid, missing command for check ' + name
        end
        unless details.subscribers.is_a?(Array) && details.subscribers.count > 0
          raise 'configuration invalid, missing subscribers for check ' + name
        end
      end
      unless @settings.client.name.is_a?(String)
        raise 'configuration invalid, client must have a name'
      end
      unless @settings.client.address.is_a?(String)
        raise 'configuration invalid, client must have an address (ip or hostname)'
      end
      unless @settings.client.subscriptions.is_a?(Array) && @settings.client.subscriptions.count > 0
        raise 'configuration invalid, client must have subscriptions'
      end
    end

    def self.read_arguments(arguments)
      options = Hash.new
      optparse = OptionParser.new do |opts|
        opts.on('-h', '--help', 'Display this screen') do
          puts opts
          exit
        end
        if $0.split('/').last == 'sensu-server'
          options[:worker] = false
          opts.on('-w', '--worker', 'Only consume jobs, no check publishing (default: false)') do
            options[:worker] = true
          end
        end
        options[:config_file] = nil
        opts.on('-c', '--config FILE', 'Sensu JSON config FILE (default: /etc/sensu/config.json)') do |file|
          options[:config_file] = file
        end
      end
      optparse.parse!(arguments)
      options
    end
  end
end
