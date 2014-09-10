require 'sensu/daemon'
require 'sensu/socket'

module Sensu
  class Client
    include Daemon

    attr_accessor :safe_mode

    def self.run(options={})
      client = self.new(options)
      EM::run do
        client.start
        client.setup_signal_traps
      end
    end

    def initialize(options={})
      super
      @safe_mode = @settings[:client][:safe_mode] || false
      @checks_in_progress = Array.new
    end

    def publish_keepalive
      keepalive = @settings[:client].merge({
        :version => VERSION,
        :timestamp => Time.now.to_i
      })
      payload = redact_sensitive(keepalive, @settings[:client][:redact])
      @logger.debug('publishing keepalive', {
        :payload => payload
      })
      @transport.publish(:direct, 'keepalives', MultiJson.dump(payload)) do |info|
        if info[:error]
          @logger.error('failed to publish keepalive', {
            :payload => payload,
            :error => info[:error].to_s
          })
        end
      end
    end

    def setup_keepalives
      @logger.debug('scheduling keepalives')
      publish_keepalive
      @timers[:run] << EM::PeriodicTimer.new(20) do
        unless @state == :paused
          publish_keepalive
        end
      end
    end

    def publish_result(check)
      payload = {
        :client => @settings[:client][:name],
        :check => check
      }
      @logger.info('publishing check result', {
        :payload => payload
      })
      @transport.publish(:direct, 'results', MultiJson.dump(payload)) do |info|
        if info[:error]
          @logger.error('failed to publish check result', {
            :payload => payload,
            :error => info[:error].to_s
          })
        end
      end
    end

    def find_client_attribute(tree, path, default)
      attribute = tree[path.shift]
      if attribute.is_a?(Hash)
        find_client_attribute(attribute, path, default)
      else
        attribute.nil? ? default : attribute
      end
    end

    def substitute_command_tokens(check)
      unmatched_tokens = Array.new
      substituted = check[:command].gsub(/:::([^:].*?):::/) do
        token, default = $1.to_s.split('|', -1)
        matched = find_client_attribute(@settings[:client], token.split('.'), default)
        if matched.nil?
          unmatched_tokens << token
        end
        matched
      end
      [substituted, unmatched_tokens]
    end

    def execute_check_command(check)
      @logger.debug('attempting to execute check command', {
        :check => check
      })
      unless @checks_in_progress.include?(check[:name])
        @checks_in_progress << check[:name]
        command, unmatched_tokens = substitute_command_tokens(check)
        if unmatched_tokens.empty?
          check[:executed] = Time.now.to_i
          started = Time.now.to_f
          Spawn.process(command, :timeout => check[:timeout]) do |output, status|
            check[:duration] = ('%.3f' % (Time.now.to_f - started)).to_f
            check[:output] = output
            check[:status] = status
            publish_result(check)
            @checks_in_progress.delete(check[:name])
          end
        else
          check[:output] = 'Unmatched command tokens: ' + unmatched_tokens.join(', ')
          check[:status] = 3
          check[:handle] = false
          publish_result(check)
          @checks_in_progress.delete(check[:name])
        end
      else
        @logger.warn('previous check command execution in progress', {
          :check => check
        })
      end
    end

    def run_check_extension(check)
      @logger.debug('attempting to run check extension', {
        :check => check
      })
      check[:executed] = Time.now.to_i
      extension = @extensions[:checks][check[:name]]
      extension.safe_run do |output, status|
        check[:output] = output
        check[:status] = status
        publish_result(check)
      end
    end

    def process_check(check)
      @logger.debug('processing check', {
        :check => check
      })
      if check.has_key?(:command)
        if @settings.check_exists?(check[:name])
          check.merge!(@settings[:checks][check[:name]])
          execute_check_command(check)
        elsif @safe_mode
          check[:output] = 'Check is not locally defined (safe mode)'
          check[:status] = 3
          check[:handle] = false
          check[:executed] = Time.now.to_i
          publish_result(check)
        else
          execute_check_command(check)
        end
      else
        if @extensions.check_exists?(check[:name])
          run_check_extension(check)
        else
          @logger.warn('unknown check extension', {
            :check => check
          })
        end
      end
    end

    def setup_subscriptions
      @logger.debug('subscribing to client subscriptions')
      @settings[:client][:subscriptions].each do |subscription|
        @logger.debug('subscribing to a subscription', {
          :subscription => subscription
        })
        funnel = [@settings[:client][:name], VERSION, Time.now.to_i].join('-')
        @transport.subscribe(:fanout, subscription, funnel) do |message_info, message|
          begin
            check = MultiJson.load(message)
            @logger.info('received check request', {
              :check => check
            })
            process_check(check)
          rescue MultiJson::ParseError => exception
            @logger.error('Failed to parse the check request with listed error',{
              :raw_check_request => message,
              :error => exception.cause.to_s
            })
          end
        end
      end
    end

    def schedule_checks(checks)
      check_count = 0
      stagger = testing? ? 0 : 2
      checks.each do |check|
        check_count += 1
        scheduling_delay = stagger * check_count % 30
        @timers[:run] << EM::Timer.new(scheduling_delay) do
          interval = testing? ? 0.5 : check[:interval]
          @timers[:run] << EM::PeriodicTimer.new(interval) do
            unless @state == :paused
              check[:issued] = Time.now.to_i
              process_check(check.dup)
            end
          end
        end
      end
    end

    def setup_standalone
      @logger.debug('scheduling standalone checks')
      standard_checks = @settings.checks.select do |check|
        check[:standalone]
      end
      extension_checks = @extensions.checks.select do |check|
        check[:standalone] && check[:interval].is_a?(Integer)
      end
      schedule_checks(standard_checks + extension_checks)
    end

    def setup_sockets
      options = @settings[:client][:socket] || Hash.new
      options[:bind] ||= '127.0.0.1'
      options[:port] ||= 3030
      @logger.debug('binding client tcp and udp sockets', {
        :options => options
      })
      EM::start_server(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
      end
      EM::open_datagram_socket(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
        socket.reply = false
      end
    end

    def complete_checks_in_progress(&block)
      @logger.info('completing checks in progress', {
        :checks_in_progress => @checks_in_progress
      })
      retry_until_true do
        if @checks_in_progress.empty?
          block.call
          true
        end
      end
    end

    def start
      setup_transport
      setup_keepalives
      setup_subscriptions
      setup_standalone
      setup_sockets
      super
    end

    def stop
      @logger.warn('stopping')
      @timers[:run].each do |timer|
        timer.cancel
      end
      @transport.unsubscribe
      complete_checks_in_progress do
        @transport.close
        super
      end
    end
  end
end
