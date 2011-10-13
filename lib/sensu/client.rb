require File.join(File.dirname(__FILE__), 'config')

module Sensu
  class Client
    def self.run(options={})
      EM.run do
        client = self.new(options)
        client.setup_amqp
        client.setup_keepalives
        client.setup_subscriptions
        client.setup_queue_monitor

        Signal.trap('INT') do
          EM.stop
        end

        Signal.trap('TERM') do
          EM.stop
        end
      end
    end

    def initialize(options={})
      config = Sensu::Config.new(:config_file => options[:config_file])
      @settings = config.settings
      @checks_in_progress = Array.new
    end

    def setup_amqp
      connection = AMQP.connect(symbolize_keys(@settings['rabbitmq']))
      @amq = MQ.new(connection)
      @keepalive_queue = @amq.queue('keepalives')
      @result_queue = @amq.queue('results')
    end

    def setup_keepalives
      @keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
      EM.add_periodic_timer(30) do
        @keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
      end
    end

    def execute_check(check)
      result = {'client' => @settings['client']['name'], 'check' => check}
      if @settings['checks'].has_key?(check['name'])
        unless @checks_in_progress.include?(check['name'])
          @checks_in_progress.push(check['name'])
          unmatched_tokens = Array.new
          command = @settings['checks'][check['name']]['command'].gsub(/:::(.*?):::/) do
            key = $1.to_s
            unmatched_tokens.push(key) unless @settings['client'].has_key?(key)
            @settings['client'][key].to_s
          end
          if unmatched_tokens.empty?
            execute = proc do
              IO.popen(command + ' 2>&1') do |io|
                result['check']['output'] = io.read
              end
              result['check']['status'] = $?.exitstatus
              result
            end
            publish = proc do |result|
              @result_queue.publish(result.to_json)
              @checks_in_progress.delete(result['check']['name'])
            end
            EM.defer(execute, publish)
          else
            result['check']['status'] = 3
            result['check']['output'] = 'Missing client attributes: ' + unmatched_tokens.join(', ')
            @result_queue.publish(result.to_json)
            @checks_in_progress.delete(check['name'])
          end
        end
      else
        result['check']['status'] = 3
        result['check']['output'] = 'Unknown check'
        @result_queue.publish(result.to_json)
        @checks_in_progress.delete(check['name'])
      end
    end

    def setup_subscriptions
      @check_queue = @amq.queue(UUIDTools::UUID.random_create.to_s, :exclusive => true)
      @settings['client']['subscriptions'].each do |exchange|
        @check_queue.bind(@amq.fanout(exchange))
      end
      @check_queue.subscribe do |check_json|
        check = JSON.parse(check_json)
        execute_check(check)
      end
    end

    def setup_queue_monitor
      EM.add_periodic_timer(5) do
        unless @check_queue.subscribed?
          @check_queue.delete
          EM.add_timer(1) do
            setup_subscriptions
          end
        end
      end
    end
  end
end
