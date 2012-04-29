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
  end
end
