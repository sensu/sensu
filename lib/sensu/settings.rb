module Sensu
  class Settings
    attr_reader :indifferent_access, :loaded_env, :loaded_files

    def initialize
      @logger = Sensu::Logger.get
      @settings = Hash.new
      [:checks, :handlers, :mutators].each do |key|
        @settings[key] = Hash.new
      end
      @indifferent_access = false
      @loaded_env = false
      @loaded_files = Array.new
    end

    def [](key)
      unless @indifferent_access
        indifferent_access!
      end
      @settings[key.to_sym]
    end

    def indifferent_access!
      @settings = indifferent_access(@settings)
      @indifferent_access = true
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
      @indifferent_access = false
      @loaded_env = true
    end

    def load_file(file)
      if File.readable?(file)
        begin
          contents = File.open(file, 'r').read
          config = JSON.parse(contents, :symbolize_names => true)
          merged = deep_merge(@settings, config)
          unless @loaded_files.empty?
            @logger.warn('config file applied changes', {
              :config_file => file,
              :changes => deep_diff(@settings, merged)
            })
          end
          @settings = merged
          @indifferent_access = false
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

    def set_env
      ENV['SENSU_CONFIG_FILES'] = @loaded_files.join(':')
    end

    [:checks, :handlers, :mutators].each do |key|
      define_method(key) do
        @settings[key].map do |name, details|
          details.merge(:name => name.to_s)
        end
      end

      define_method((key.to_s.chop + '_exists?').to_sym) do |name|
        @settings[key].has_key?(name.to_sym)
      end
    end

    def validate
      @logger.debug('validating settings')
      validate_checks
      case File.basename($0)
      when 'rake'
        validate_client
        validate_api
        validate_server
      when 'sensu-client'
        validate_client
      when 'sensu-api'
        validate_api
      when 'sensu-server'
        validate_server
      end
      @logger.debug('settings are valid')
    end

    private

    def indifferent_access(hash)
      hash = indifferent_hash.merge(hash)
      hash.each do |key, value|
        if value.is_a?(Hash)
          hash[key] = indifferent_access(value)
        end
      end
    end

    def indifferent_hash
      Hash.new do |hash, key|
        if key.is_a?(String)
          hash[key.to_sym]
        end
      end
    end

    def deep_merge(hash_one, hash_two)
      merged = hash_one.dup
      hash_two.each do |key, value|
        merged[key] = case
        when hash_one[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge(hash_one[key], value)
        when hash_one[key].is_a?(Array) && value.is_a?(Array)
          hash_one[key].concat(value).uniq
        else
          value
        end
      end
      merged
    end

    def deep_diff(hash_one, hash_two)
      keys = hash_one.keys.concat(hash_two.keys).uniq
      keys.inject(Hash.new) do |diff, key|
        unless hash_one[key] == hash_two[key]
          if hash_one[key].is_a?(Hash) && hash_two[key].is_a?(Hash)
            diff[key] = deep_diff(hash_one[key], hash_two[key])
          else
            diff[key] = [hash_one[key], hash_two[key]]
          end
        end
        diff
      end
    end

    def invalid(reason, details={})
      @logger.fatal('invalid settings', {
        :reason => reason
      }.merge(details))
      @logger.fatal('SENSU NOT RUNNING!')
      exit 2
    end

    def validate_checks
      unless @settings[:checks].is_a?(Hash)
        invalid('checks must be a hash')
      end
      checks.each do |check|
        unless check[:interval].is_a?(Integer) && check[:interval] > 0
          invalid('check is missing interval', {
            :check => check
          })
        end
        unless check[:command].is_a?(String)
          invalid('check is missing command', {
            :check => check
          })
        end
        unless check[:standalone]
          unless check[:subscribers].is_a?(Array) && check[:subscribers].count > 0
            invalid('check is missing subscribers', {
              :check => check
            })
          end
          check[:subscribers].each do |subscriber|
            unless subscriber.is_a?(String) && !subscriber.empty?
              invalid('check subscribers must each be a string', {
                :check => check
              })
            end
          end
        end
        if check.has_key?(:handler)
          unless check[:handler].is_a?(String)
            invalid('check handler must be a string', {
              :check => check
            })
          end
        end
        if check.has_key?(:handlers)
          unless check[:handlers].is_a?(Array)
            invalid('check handlers must be an array', {
              :check => check
            })
          end
        end
        if check.has_key?(:subdue)
          unless check[:subdue].is_a?(Hash)
            invalid('check subdue must be a hash', {
              :check => check
            })
          end
          if check[:subdue].has_key?(:begin) || check[:subdue].has_key?(:end)
            begin
              Time.parse(check[:subdue][:begin])
              Time.parse(check[:subdue][:end])
            rescue
              invalid('check subdue begin & end times must be valid', {
                :check => check
              })
            end
          end
          if check[:subdue].has_key?(:days)
            unless check[:subdue][:days].is_a?(Array)
              invalid('check subdue days must be an array', {
                :check => check
              })
            end
            check[:subdue][:days].each do |day|
              days = %w[sunday monday tuesday wednesday thursday friday saturday]
              unless day.is_a?(String) && days.include?(day.downcase)
                invalid('check subdue days must be valid days of the week', {
                  :check => check
                })
              end
            end
          end
          if check[:subdue].has_key?(:exceptions)
            unless check[:subdue][:exceptions].is_a?(Array)
              invalid('check subdue exceptions must be an array', {
                :check => check
              })
            end
            check[:subdue][:exceptions].each do |exception|
              unless exception.is_a?(Hash)
                invalid('check subdue exceptions must each be a hash', {
                  :check => check
                })
              end
              if exception.has_key?(:begin) || exception.has_key?(:end)
                begin
                  Time.parse(exception[:begin])
                  Time.parse(exception[:end])
                rescue
                  invalid('check subdue exception begin & end times must be valid', {
                    :check => check
                  })
                end
              end
            end
          end
        end
      end
    end

    def validate_client
      unless @settings[:client].is_a?(Hash)
        invalid('missing client configuration')
      end
      unless @settings[:client][:name].is_a?(String)
        invalid('client must have a name')
      end
      unless @settings[:client][:address].is_a?(String)
        invalid('client must have an address')
      end
      unless @settings[:client][:subscriptions].is_a?(Array) && !@settings[:client][:subscriptions].empty?
        invalid('client must have subscriptions')
      end
      @settings[:client][:subscriptions].each do |subscription|
        unless subscription.is_a?(String) && !subscription.empty?
          invalid('client subscriptions must each be a string')
        end
      end
    end

    def validate_api
      unless @settings[:api].is_a?(Hash)
        invalid('missing api configuration')
      end
      unless @settings[:api][:port].is_a?(Integer)
        invalid('api port must be an integer')
      end
      if @settings[:api].has_key?(:user) || @settings[:api].has_key?(:password)
        unless @settings[:api][:user].is_a?(String)
          invalid('api user must be a string')
        end
        unless @settings[:api][:password].is_a?(String)
          invalid('api password must be a string')
        end
      end
    end

    def validate_server
      unless @settings[:handlers].is_a?(Hash)
        invalid('handlers must be a hash')
      end
      unless @settings[:handlers].include?(:default)
        invalid('missing default handler')
      end
      handlers.each do |handler|
        unless handler[:type].is_a?(String)
          invalid('handler is missing type', {
            :handler => handler
          })
        end
        if handler.has_key?(:severities)
          unless handler[:severities].is_a?(Array) && !handler[:severities].empty?
            invalid('handler severities must be an array and not empty', {
              :handler => handler
            })
          end
          handler[:severities].each do |severity|
            unless Sensu::SEVERITIES.include?(severity)
              invalid('handler severities are invalid', {
                :handler => handler
              })
            end
          end
        end
        case handler[:type]
        when 'pipe'
          unless handler[:command].is_a?(String)
            invalid('handler is missing command', {
              :handler => handler
            })
          end
        when 'tcp', 'udp'
          unless handler[:socket].is_a?(Hash)
            invalid('handler is missing socket hash', {
              :handler => handler
            })
          end
          unless handler[:socket][:host].is_a?(String)
            invalid('handler is missing socket host', {
              :handler => handler
            })
          end
          unless handler[:socket][:port].is_a?(Integer)
            invalid('handler is missing socket port', {
              :handler => handler
            })
          end
        when 'amqp'
          unless handler[:exchange].is_a?(Hash)
            invalid('handler is missing exchange hash', {
              :handler => handler
            })
          end
          unless handler[:exchange][:name].is_a?(String)
            invalid('handler is missing exchange name', {
              :handler => handler
            })
          end
          if handler[:exchange].has_key?(:type)
            unless %w[direct fanout topic].include?(handler[:exchange][:type])
              invalid('handler exchange type is invalid', {
                :handler => handler
              })
            end
          end
        when 'set'
          unless handler[:handlers].is_a?(Array) && handler[:handlers].count > 0
            invalid('handler set is missing handlers', {
              :handler => handler
            })
          end
        else
          invalid('unknown handler type', {
            :handler => handler
          })
        end
      end
      unless @settings[:mutators].is_a?(Hash)
        invalid('mutators must be a hash')
      end
      mutators.each do |mutator|
        unless mutator[:command].is_a?(String)
          invalid('mutator is missing command', {
            :mutator => mutator
          })
        end
      end
    end
  end
end
