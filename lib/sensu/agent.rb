gem 'multi_json', '1.10.1'

gem 'sensu-em', '2.4.0'
gem 'sensu-logger', '1.0.0'
gem 'sensu-settings', '1.2.0'
gem 'sensu-transport', '2.4.0'

require 'time'

require 'sensu/logger'
require 'sensu/settings'
require 'sensu/extensions'
require 'sensu/transport'

require 'sensu/constants'
require 'sensu/utilities'
require 'sensu/spawn'

module Sensu
  class Agent
    include Utilities

    def initialize(settings, checks, extensions, transport, logger, testing)
      @logger = logger
      @agent = settings
      @clients = {}
      @safe_mode = settings[:safe_mode] || false
      @checks = checks
      @extensions = extensions
      @transport = transport
      @timers = { :run => [] }
      @testing = testing
      @state = :initialized
    end # initialize

    def start
      # start everything only at the next tick,
      # to give extensions a chance to initialize
      EM.next_tick do
        setup_represented_clients
        setup_keepalives
        setup_subscriptions
        setup_standalone
        @state = :running
      end
    end # start

    def pause
      unless @state == :pausing || @state == :paused
        @state = :pausing
        @timers[:run].each do |timer|
          timer.cancel
        end
        @timers[:run].clear
        @state = :paused
      end
    end # pause

    def resume
      if @state == :paused
        start
      end
    end # resume

    def stop
      @logger.warn('stopping')
      pause
      @state = :stopping
      complete_checks_in_progress do
        @transport.close
        super
      end
    end # stop

    private

    def represented_clients
      @clients.map do |name, details|
        details.merge(:name => name.to_s)
      end
    end # represented clients

    def setup_represented_clients
      @logger.debug('registering represented clients', {
        :agent => @agent
      })
      if @agent[:represents]
        if @agent[:represents][:address]
          # having an address defined means we are fully representing our client
          @logger.debug('fully defined client found in specs', {
            :represents => @agent[:represents]
          })
          client_name = @agent[:represents][:name].to_sym
          client_details = { :address => @agent[:represents][:address] }
          register_represented_clients({ client_name => client_details })
        else
          # when we are provided with only a name or a regex we are only
          # partially representing the client which should be already registered
          # with the server.
          # TODO: add client lookup by regex
          # TODO: stop sending keepalive for these type of clients
          # TODO: add validation rules for regex config
        end
      else
        # when no represents section is present in the config, we have to
        # discover the represented clients by running a command
        @logger.debug('scheduling represented clients discovery')
        discover_represented_clients
        interval = @agent[:discovery][:interval] || 20
        @timers[:run] << EM::PeriodicTimer.new(interval) do
          discover_represented_clients
        end
      end
    end # setup_represented_clients

    def discover_represented_clients
      @logger.debug('attempting to discover clients', {
        :discovery => @agent[:discovery]
      })
      if @agent[:discovery].has_key?(:command)
        execute_discovery_command
      else
        run_discovery_extension
      end
    end # discover_represented_clients

    def execute_discovery_command
      command, unmatched_tokens = substitute_tokens(@agent, @agent[:discovery][:command])
      if unmatched_tokens.empty?
        Spawn.process(command, :timeout => @agent[:discovery][:timeout]) do |output, status|
          begin
            clients = MultiJson.load(output)[:clients]
            process_discovery_result(clients, status)
          rescue MultiJson::ParseError => error
            @logger.error('failed to parse the clients discovery command output', {
              :output => output,
              :error => error.to_s
            })
          end
        end
      else
        @logger.error('unmatched tokens in clients discovery command', {
          :discovery => @agent[:discovery],
          :unmatched_tokens => unmatched_tokens
        })
        process_discovery_result({}, 3)
      end
    end # execute_discovery_command

    def run_discovery_extension
      @logger.debug('attempting to run discovery extension', {
        :discovery => @agent[:discovery]
      })
      extension = @extensions[:discoverers][@agent[:discovery][:extension]]
      extension.safe_run(@agent[:discovery]) do |output, status|
        process_discovery_result(output, status)
      end
    end # run_discovery_extension

    def process_discovery_result(output, status)
      clients = {}
      if status != 0
        @logger.error('clients discovery failed', {
          :discovery => @agent[:discovery],
          :status => status,
          :output => output
          })
      end
      begin
        clients = MultiJson.load(output)[:clients]
      rescue MultiJson::ParseError => error
        @logger.error('failed to parse the clients discovery output', {
          :output => output,
          :error => error.to_s
        })
      end
      # TODO: should we do anything if discovery fails or should we leave
      # the already represented clients in place?
      register_represented_clients(clients || {})
    end # process_discovery_result

    def register_represented_clients(clients)
      already_represented_clients = @clients.select { |name, _|
        clients.has_key?(name)
      }
      @clients = clients.merge(clients) { |name, new_details, _|
        new_details.merge(@agent.reject { |k, v|
          # reject agent specific attributes
          k == :name or
          k == :address or
          k == :represents or
          k == :discovery
        }).merge(
          { :checks_in_progress => [] }
        )
      }.merge(already_represented_clients) { |name, new_details, old_details|
        new_details.merge(
          { :checks_in_progress => old_details[:checks_in_progress] || [] }
        )
      }
      @logger.info('registered represented clients', {
        :count => represented_clients.size
      })
      @logger.debug('registered represented clients', {
        :represented_clients => represented_clients
      })
    end # register_represented_clients

    def setup_keepalives
      @logger.debug('scheduling keepalives')
      publish_keepalives
      @timers[:run] << EM::PeriodicTimer.new(20) do
        publish_keepalives
      end
    end # setup_keepalives

    def publish_keepalives
      represented_clients.each { |client| publish_keepalive(client) }
    end # publish_keepalives

    def publish_keepalive(client)
      keepalive = client.merge({
        :version => VERSION,
        :timestamp => Time.now.to_i
      }).reject { |k, v| k == :checks_in_progress }
      payload = redact_sensitive(keepalive, @agent[:redact])
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
    end # publish_keepalive

    def setup_subscriptions
      @logger.debug('subscribing to agent subscriptions')
      @agent[:subscriptions].each do |subscription|
        @logger.debug('subscribing to', {
          :subscription => subscription
        })
        funnel = [@agent[:name], VERSION, Time.now.to_i].join('-')
        @transport.subscribe(:fanout, subscription, funnel) do |message_info, message|
          begin
            check = MultiJson.load(message)
            @logger.info('received check request', {
              :check => check
            })
            process_check(check)
          rescue MultiJson::ParseError => error
            @logger.error('failed to parse the check request payload', {
              :message => message,
              :error => error.to_s
            })
          end
        end
      end
    end # setup_subscriptions

    def setup_standalone
      @logger.debug('scheduling standalone checks')
      standard_checks = []
      @checks.each do |name, options|
        standard_checks << options.merge(:name => name.to_s) if options[:standalone]
      end
      extension_checks = @extensions.checks.select do |check|
        check[:standalone] && check[:interval].is_a?(Integer)
      end
      schedule_checks(standard_checks + extension_checks)
    end # setup_standalone

    def schedule_checks(checks)
      check_count = 0
      stagger = @testing ? 0 : 2
      checks.each do |name, options|
        check_count += 1
        scheduling_delay = stagger * check_count % 30
        @timers[:run] << EM::Timer.new(scheduling_delay) do
          interval = @testing ? 0.5 : options[:interval]
          @timers[:run] << EM::PeriodicTimer.new(interval) do
            options[:issued] = Time.now.to_i
            process_check(options.merge(:name => name.to_s))
          end
        end
      end
    end # schedule_checks

    def process_check(check)
      @logger.debug('processing check', {
        :check => check
      })
      if @safe_mode and not @checks.has_key?(check[:name])
        check[:output] = 'Check is not locally defined (safe mode)'
        check[:status] = 3
        check[:handle] = false
        check[:executed] = Time.now.to_i
        represented_clients.each { |client| publish_result(client, check) }
      else
        runnable_check = check.merge(@checks[check[:name]] || {})
        if runnable_check.has_key?(:command)
          represented_clients.each { |client| execute_check_command(client, runnable_check) }
        else
          if @extensions.check_exists?(runnable_check[:extension])
            represented_clients.each { |client| run_check_extension(client, runnable_check) }
          else
            @logger.warn('unknown check extension', {
              :check => runnable_check
            })
          end
        end
      end
    end # process_check

    def execute_check_command(client, check)
      @logger.debug('attempting to execute check command', {
        :client => client[:name],
        :check => check
      })
      unless client[:checks_in_progress].include?(check[:name])
        client[:checks_in_progress] << check[:name]
        command, unmatched_tokens = substitute_tokens(client, check[:command])
        if unmatched_tokens.empty?
          check[:executed] = Time.now.to_i
          started = Time.now.to_f
          Spawn.process(command, :timeout => check[:timeout]) do |output, status|
            check[:duration] = ('%.3f' % (Time.now.to_f - started)).to_f
            check[:output] = output
            check[:status] = status
            publish_result(client, check)
            client[:checks_in_progress].delete(check[:name])
          end
        else
          check[:output] = 'Unmatched command tokens: ' + unmatched_tokens.join(', ')
          check[:status] = 3
          check[:handle] = false
          publish_result(client, check)
          client[:checks_in_progress].delete(check[:name])
        end
      else
        @logger.warn('previous check command execution in progress', {
          :client => client[:name],
          :check => check
        })
      end
    end # execute_check_command

    def run_check_extension(client, check)
      @logger.debug('attempting to run check extension', {
        :client => client[:name],
        :check => check
      })
      unless client[:checks_in_progress].include?(check[:name])
        client[:checks_in_progress] << check[:name]
        extension = @extensions[:checks][check[:extension]]
        # ignore unmatched tokens as they will be replaced by the check.
        substituted_check, _ = substitute_tokens(client, check)
        check[:executed] = Time.now.to_i
        started = Time.now.to_f
        extension.safe_run(substituted_check) do |output, status|
          check[:duration] = ('%.3f' % (Time.now.to_f - started)).to_f
          check[:output] = output
          check[:status] = status
          publish_result(client, check)
          client[:checks_in_progress].delete(check[:name])
        end
      else
        @logger.warn('previous check command execution in progress', {
          :client => client[:name],
          :check => check
        })
      end
    end # run_check_extension

    def substitute_tokens(client, tokenized)
      if tokenized.is_a?(Hash)
        unmatched_tokens = Array.new
        substituted_hash = tokenized.inject({}) do |hash, pair|
          key = pair[0]
          value = pair[1]
          substituted, unmatched = substitute_tokens(client, value)
          unmatched_tokens << unmatched
          hash.merge(key => substituted)
        end
        [substituted_hash, unmatched_tokens.flatten]
      elsif tokenized.is_a?(String)
        unmatched_tokens = Array.new
        substituted_string = tokenized.gsub(/:::([^:].*?):::/) do
          token = $&
          token_name, default = $1.to_s.split('|', -1)
          matched = find_attribute(client, token_name.split('.'), default)
          if matched.nil?
            unmatched_tokens << token_name
            token # return token, as checks might replace this on their own
          else
            matched
          end
        end
        [substituted_string, unmatched_tokens]
      else
        [tokenized, []]
      end
    end # substitute_tokens

    def find_attribute(tree, path, default)
      key = path.shift
      attribute = tree[key] || tree[key.to_sym]
      if attribute.is_a?(Hash)
        find_attribute(attribute, path, default)
      else
        attribute.nil? ? default : attribute
      end
    end # find_attribute

    def publish_result(client, check)
      payload = {
        :client => client[:name],
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
    end # publish_result

    def complete_checks_in_progress
      @logger.info('completing checks in progress', {
        :checks_in_progress => represented_clients.reduce([]) { |checks_in_progress, client|
          checks_in_progress + client[:checks_in_progress]
        }
      })
      retry_until_true do
        represented_clients.all { |client| client[:checks_in_progress].empty? }
      end
    end # complete_checks_in_progress

  end # class Agent
end # module Sensu
