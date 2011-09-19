require File.join(File.dirname(__FILE__), 'config')

module Sensu
  class Client
    def self.run(options={})
      EM.run do
        client = self.new(options)
        client.setup_amqp
        client.setup_keepalives
        client.setup_subscriptions

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
      @result_queue = @amq.queue('results')
    end

    def setup_keepalives
      keepalive_queue = @amq.queue('keepalives')
      keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
      EM.add_periodic_timer(30) do
        keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
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
            EM.system('sh', '-c', command + ' 2>&1') do |output, status|
              result['check'].merge!({'status' => status.exitstatus, 'output' => output})
              @result_queue.publish(result.to_json)
              @checks_in_progress.delete(check['name'])
            end
          else
            result['check'].merge!({'status' => 3, 'output' => 'Missing client attributes: ' + unmatched_tokens.join(', ')})
            @result_queue.publish(result.to_json)
            @checks_in_progress.delete(check['name'])
          end
        end
      else
        result['check'].merge!({'status' => 3, 'output' => 'Unknown check'})
        @result_queue.publish(result.to_json)
        @checks_in_progress.delete(check['name'])
      end
    end

    def setup_subscriptions
      uniq_queue = @amq.queue(UUIDTools::UUID.random_create.to_s, :exclusive => true)
      @settings['client']['subscriptions'].each do |exchange|
        uniq_queue.bind(@amq.fanout(exchange))
      end
      EM.add_periodic_timer(0.5) do
        unless uniq_queue.subscribed?
          uniq_queue.subscribe(:ack => true) do |check_json|
            check = JSON.parse(check_json)
            execute_check(check)
          end
        end
      end
    end
  end
end
