module Sensu
  class Settings
    include Utilities

    attr_reader :indifferent_access, :loaded_env, :loaded_files

    def initialize
      @logger = Logger.get
      @settings = Hash.new
      SETTINGS_CATEGORIES.each do |category|
        @settings[category] = Hash.new
      end
      @indifferent_access = false
      @loaded_env = false
      @loaded_files = Array.new
    end

    def indifferent_access!
      @settings = with_indifferent_access(@settings)
      @indifferent_access = true
    end

    def to_hash
      unless @indifferent_access
        indifferent_access!
      end
      @settings
    end

    def [](key)
      to_hash[key]
    end

    SETTINGS_CATEGORIES.each do |category|
      define_method(category) do
        @settings[category].map do |name, details|
          details.merge(:name => name.to_s)
        end
      end

      type = category.to_s.chop

      define_method((type + '_exists?').to_sym) do |name|
        @settings[category].has_key?(name.to_sym)
      end

      define_method(('invalid_' + type).to_sym) do |details, reason|
        invalid(reason, {
          type => details
        })
      end
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
      @logger.debug('loading config file', {
        :config_file => file
      })
      if File.file?(file) && File.readable?(file)
        begin
          contents = File.open(file, 'r').read
          config = Oj.load(contents)
          merged = deep_merge(@settings, config)
          unless @loaded_files.empty?
            @logger.warn('config file applied changes', {
              :config_file => file,
              :changes => deep_diff(@settings, merged)
            })
          end
          @settings = merged
          @indifferent_access = false
          @loaded_files << file
        rescue Oj::ParseError => error
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

    def load_directory(directory)
      path = directory.gsub(/\\(?=\S)/, '/')
      Dir.glob(File.join(path, '**/*.json')).each do |file|
        load_file(file)
      end
    end

    def set_env
      ENV['SENSU_CONFIG_FILES'] = @loaded_files.join(':')
    end

    def validate
      @logger.debug('validating settings')
      SETTINGS_CATEGORIES.each do |category|
        unless @settings[category].is_a?(Hash)
          invalid(category.to_s + ' must be a hash')
        end
        send(category).each do |details|
          send(('validate_' + category.to_s.chop).to_sym, details)
        end
      end
      case File.basename($0)
      when 'sensu-client'
        validate_client
      when 'sensu-api'
        validate_api
      when 'rspec'
        validate_client
        validate_api
      end
      @logger.debug('settings are valid')
    end

    private

    def invalid(reason, data={})
      @logger.fatal('invalid settings', {
        :reason => reason
      }.merge(data))
      @logger.fatal('SENSU NOT RUNNING!')
      exit 2
    end

    def validate_subdue(type, details)
      condition = details[:subdue]
      data = {
        type => details
      }
      unless condition.is_a?(Hash)
        invalid(type + ' subdue must be a hash', data)
      end
      if condition.has_key?(:at)
        unless %w[handler publisher].include?(condition[:at])
          invalid(type + ' subdue at must be either handler or publisher', data)
        end
      end
      if condition.has_key?(:begin) || condition.has_key?(:end)
        begin
          Time.parse(condition[:begin])
          Time.parse(condition[:end])
        rescue
          invalid(type + ' subdue begin & end times must be valid', data)
        end
      end
      if condition.has_key?(:days)
        unless condition[:days].is_a?(Array)
          invalid(type + ' subdue days must be an array', data)
        end
        condition[:days].each do |day|
          days = %w[sunday monday tuesday wednesday thursday friday saturday]
          unless day.is_a?(String) && days.include?(day.downcase)
            invalid(type + ' subdue days must be valid days of the week', data)
          end
        end
      end
      if condition.has_key?(:exceptions)
        unless condition[:exceptions].is_a?(Array)
          invalid(type + ' subdue exceptions must be an array', data)
        end
        condition[:exceptions].each do |exception|
          unless exception.is_a?(Hash)
            invalid(type + ' subdue exceptions must each be a hash', data)
          end
          if exception.has_key?(:begin) || exception.has_key?(:end)
            begin
              Time.parse(exception[:begin])
              Time.parse(exception[:end])
            rescue
              invalid(type + ' subdue exception begin & end times must be valid', data)
            end
          end
        end
      end
    end

    def validate_check(check)
      unless check[:name] =~ /^[\w-]+$/
        invalid_check(check, 'check name cannot contain spaces or special characters')
      end
      unless (check[:interval].is_a?(Integer) && check[:interval] > 0) || !check[:publish]
        invalid_check(check, 'check is missing interval')
      end
      unless check[:command].is_a?(String)
        invalid_check(check, 'check is missing command')
      end
      if check.has_key?(:standalone)
        unless !!check[:standalone] == check[:standalone]
          invalid_check(check, 'check standalone must be boolean')
        end
      end
      unless check[:standalone]
        unless check[:subscribers].is_a?(Array)
          invalid_check(check, 'check is missing subscribers')
        end
        check[:subscribers].each do |subscriber|
          unless subscriber.is_a?(String) && !subscriber.empty?
            invalid_check(check, 'check subscribers must each be a string')
          end
        end
      end
      if check.has_key?(:timeout)
        unless check[:timeout].is_a?(Numeric)
          invalid_check(check, 'check timeout must be numeric')
        end
      end
      if check.has_key?(:handler)
        unless check[:handler].is_a?(String)
          invalid_check(check, 'check handler must be a string')
        end
      end
      if check.has_key?(:handlers)
        unless check[:handlers].is_a?(Array)
          invalid_check(check, 'check handlers must be an array')
        end
        check[:handlers].each do |handler_name|
          unless handler_name.is_a?(String)
            invalid_check(check, 'check handlers must each be a string')
          end
        end
      end
      if check.has_key?(:low_flap_threshold) || check.has_key?(:high_flap_threshold)
        unless check[:low_flap_threshold].is_a?(Integer)
          invalid_check(check, 'check low flap threshold must be numeric')
        end
        unless check[:high_flap_threshold].is_a?(Integer)
          invalid_check(check, 'check high flap threshold must be numeric')
        end
      end
      if check.has_key?(:subdue)
        validate_subdue('check', check)
      end
    end

    def validate_mutator(mutator)
      unless mutator[:command].is_a?(String)
        invalid_mutator(mutator, 'mutator is missing command')
      end
    end

    def validate_filter(filter)
      unless filter[:attributes].is_a?(Hash)
        invalid_filter(filter, 'filter attributes must be a hash')
      end
      if filter.has_key?(:negate)
        unless !!filter[:negate] == filter[:negate]
          invalid_filter(filter, 'filter negate must be boolean')
        end
      end
    end

    def validate_handler(handler)
      unless handler[:type].is_a?(String)
        invalid_handler(handler, 'handler is missing type')
      end
      case handler[:type]
      when 'pipe'
        unless handler[:command].is_a?(String)
          invalid_handler(handler, 'handler is missing command')
        end
      when 'tcp', 'udp'
        unless handler[:socket].is_a?(Hash)
          invalid_handler(handler, 'handler is missing socket hash')
        end
        unless handler[:socket][:host].is_a?(String)
          invalid_handler(handler, 'handler is missing socket host')
        end
        unless handler[:socket][:port].is_a?(Integer)
          invalid_handler(handler, 'handler is missing socket port')
        end
        if handler[:socket].has_key?(:timeout)
          unless handler[:socket][:timeout].is_a?(Integer)
            invalid_handler(handler, 'handler socket timeout must be an integer')
          end
        end
      when 'amqp'
        unless handler[:exchange].is_a?(Hash)
          invalid_handler(handler, 'handler is missing exchange hash')
        end
        unless handler[:exchange][:name].is_a?(String)
          invalid_handler(handler, 'handler is missing exchange name')
        end
        if handler[:exchange].has_key?(:type)
          unless %w[direct fanout topic].include?(handler[:exchange][:type])
            invalid_handler(handler, 'handler exchange type is invalid')
          end
        end
      when 'set'
        unless handler[:handlers].is_a?(Array)
          invalid_handler(handler, 'handler set handlers must be an array')
        end
        handler[:handlers].each do |handler_name|
          unless handler_name.is_a?(String)
            invalid_handler(handler, 'handler set handlers must each be a string')
          end
          if handler_exists?(handler_name) && @settings[:handlers][handler_name.to_sym][:type] == 'set'
            invalid_handler(handler, 'handler sets cannot be nested')
          end
        end
      else
        invalid_handler(handler, 'unknown handler type')
      end
      if handler.has_key?(:filter)
        unless handler[:filter].is_a?(String)
          invalid_handler(handler, 'handler filter must be a string')
        end
      end
      if handler.has_key?(:filters)
        unless handler[:filters].is_a?(Array)
          invalid_handler(handler, 'handler filters must be an array')
        end
        handler[:filters].each do |filter_name|
          unless filter_name.is_a?(String)
            invalid_handler(handler, 'handler filters items must be strings')
          end
        end
      end
      if handler.has_key?(:mutator)
        unless handler[:mutator].is_a?(String)
          invalid_handler(handler, 'handler mutator must be a string')
        end
      end
      if handler.has_key?(:handle_flapping)
        unless !!handler[:handle_flapping] == handler[:handle_flapping]
          invalid_handler(handler, 'handler handle_flapping must be boolean')
        end
      end
      if handler.has_key?(:severities)
        unless handler[:severities].is_a?(Array) && !handler[:severities].empty?
          invalid_handler(handler, 'handler severities must be an array and not empty')
        end
        handler[:severities].each do |severity|
          unless SEVERITIES.include?(severity)
            invalid_handler(handler, 'handler severities are invalid')
          end
        end
      end
      if handler.has_key?(:subdue)
        validate_subdue('handler', handler)
      end
    end

    def validate_client
      unless @settings[:client].is_a?(Hash)
        invalid('missing client configuration')
      end
      unless @settings[:client][:name].is_a?(String) && !@settings[:client][:name].empty?
        invalid('client must have a name')
      end
      unless @settings[:client][:address].is_a?(String)
        invalid('client must have an address')
      end
      unless @settings[:client][:subscriptions].is_a?(Array)
        invalid('client must have subscriptions')
      end
      @settings[:client][:subscriptions].each do |subscription|
        unless subscription.is_a?(String) && !subscription.empty?
          invalid('client subscriptions must each be a string')
        end
      end
      if @settings[:client].has_key?(:keepalive)
        unless @settings[:client][:keepalive].is_a?(Hash)
          invalid('client keepalive must be a hash')
        end
        if @settings[:client][:keepalive].has_key?(:handler)
          unless @settings[:client][:keepalive][:handler].is_a?(String)
            invalid('client keepalive handler must be a string')
          end
        end
        if @settings[:client][:keepalive].has_key?(:handlers)
          handlers = @settings[:client][:keepalive][:handlers]
          unless handlers.is_a?(Array)
            invalid('client keepalive handlers must be an array')
          end
          handlers.each do |handler_name|
            unless handler_name.is_a?(String)
              invalid('client keepalive handlers must each be a string')
            end
          end
        end
        if @settings[:client][:keepalive].has_key?(:thresholds)
          thresholds = @settings[:client][:keepalive][:thresholds]
          unless thresholds.is_a?(Hash)
            invalid('client keepalive thresholds must be a hash')
          end
          if thresholds.has_key?(:warning) || thresholds.has_key?(:critical)
            unless thresholds[:warning].is_a?(Integer)
              invalid('client keepalive warning threshold must be an integer')
            end
            unless thresholds[:critical].is_a?(Integer)
              invalid('client keepalive critical threshold must be an integer')
            end
          end
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
  end
end
