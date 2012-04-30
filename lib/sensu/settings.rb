module Sensu
  class Settings
    attr_accessor :loaded_env, :loaded_files

    def initialize
      @logger = Cabin::Channel.get($0)
      @settings = Hash.new
      @loaded_env = false
      @loaded_files = Array.new
    end

    def [](key)
      @settings[key.to_sym]
    end

    def to_hash
      @settings
    end

    def load_env
      if ENV['RABBITMQ_URL']
        @settings[:rabbitmq] = ENV['RABBITMQ_URL']
        @logger.warn('using rabbitmq url environment variable', {
          :rabbitmq_url => ENV['RABBITMQ_URL']
        })
      end
      ENV['REDIS_URL'] ||= ENV['REDISTOGO_URL']
      if ENV['REDIS_URL']
        @settings[:redis] = ENV['REDIS_URL']
        @logger.warn('using redis url environment variable', {
          :redis_url => ENV['REDIS_URL']
        })
      end
      ENV['API_PORT'] ||= ENV['PORT']
      if ENV['API_PORT']
        @settings[:api] ||= Hash.new
        @settings[:api][:port] = ENV['API_PORT']
        @logger.warn('using api port environment variable', {
          :api_port => ENV['API_PORT']
        })
      end
      @loaded_env = true
    end

    def load_file(file)
      if File.readable?(file)
        begin
          contents = File.open(file, 'r').read
          config = JSON.parse(contents, :symbolize_names => true)
          merged = @settings.deep_merge(config)
          unless @loaded_files.empty?
            @logger.warn('config file applied changes', {
              :config_file => file,
              :changes => @settings.deep_diff(merged)
            })
          end
          @settings = merged
          @loaded_files.push(file)
        rescue JSON::ParserError => error
          @logger.error('config file must be valid json', {
            :config_file => file,
            :error => error.to_s
          })
          @logger.warn('ignoring config file', {
            :config_file => file
          })
        end
      else
        @logger.error('config file does not exist or is not readable', {
          :config_file => file
        })
        @logger.warn('ignoring config file', {
          :config_file => file
        })
      end
    end

    def map_checks
      @settings[:checks].map do |check_name, check_details|
        check_details.merge(:name => check_name.to_s)
      end
    end

    def validate
      validate_checks
      case File.basename($0)
      when 'rake'
        validate_client
        validate_api
      when 'sensu-api'
        validate_api
      when 'sensu-client'
        validate_client
      end
    end

    private

    def validate_checks
      unless @settings.has_key?(:checks)
        raise('missing check configuration')
      end
      map_checks.each do |check|
        unless check[:interval].is_a?(Integer) && check[:interval] > 0
          raise('missing interval for check: ' + check[:name])
        end
        unless check[:command].is_a?(String)
          raise('missing command for check: ' + check[:name])
        end
        unless check[:standalone]
          unless check[:subscribers].is_a?(Array) && check[:subscribers].count > 0
            raise('missing subscribers for check: ' + check[:name])
          end
          check[:subscribers].each do |subscriber|
            unless subscriber.is_a?(String) && !subscriber.empty?
              raise('a check subscriber must be a string for check: ' + check[:name])
            end
          end
        end
        if check.has_key?(:handler)
          unless check[:handler].is_a?(String)
            raise('handler must be a string for check: ' + check[:name])
          end
        end
        if check.has_key?(:handlers)
          unless check[:handlers].is_a?(Array)
            raise('handlers must be an array for check: ' + check[:name])
          end
        end
      end
    end

    def validate_client
      unless @settings.has_key?(:client)
        raise('missing client configuration')
      end
      unless @settings[:client][:name].is_a?(String)
        raise('client must have a name')
      end
      unless @settings[:client][:address].is_a?(String)
        raise('client must have an address')
      end
      unless @settings[:client][:subscriptions].is_a?(Array) && @settings[:client][:subscriptions].count > 0
        raise('client must have subscriptions')
      end
      @settings[:client][:subscriptions].each do |subscription|
        unless subscription.is_a?(String) && !subscription.empty?
          raise('a client subscription must be a string')
        end
      end
    end

    def validate_api
      unless @settings.has_key?(:api)
        raise('missing api configuration')
      end
      unless @settings[:api][:port].is_a?(Integer)
        raise('api port must be an integer')
      end
      if @settings[:api].has_key?(:user) || @settings[:api].has_key?(:password)
        unless @settings[:api][:user].is_a?(String)
          raise('api user must be a string')
        end
        unless @settings[:api][:password].is_a?(String)
          raise('api password must be a string')
        end
      end
    end
  end
end
