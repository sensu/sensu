require File.join(File.dirname(__FILE__), 'config')

module Sensu
  class Client
    attr_accessor :settings

    def self.run(options={})
      EM.run do
        client = self.new(options)
        client.setup_amqp
        client.setup_keep_alives
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
    end

    def setup_amqp
      connection = AMQP.connect(symbolize_keys(@settings['rabbitmq']))
      @amq = AMQP::Channel.new(connection)
    end

    def setup_keep_alives
      keepalive_queue = @amq.queue('keepalives')
      keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
      EM.add_periodic_timer(30) do
        keepalive_queue.publish(@settings['client'].merge({'timestamp' => Time.now.to_i}).to_json)
      end
    end

    def setup_subscriptions
      @result_queue = @amq.queue('results')
      @checks_in_progress = Array.new
      @settings['client']['subscriptions'].each do |exchange|
        uniq_queue_name = UUIDTools::UUID.random_create.to_s
        @amq.queue(uniq_queue_name, :auto_delete => true).bind(@amq.fanout(exchange)).subscribe do |check_json|
          check = JSON.parse(check_json)
          execute_check(check)
        end
      end
    end

    def execute_check(check)
      if @settings['checks'][check['name']]
        unless @checks_in_progress.include?(check['name'])
          @checks_in_progress.push(check['name'])
          command = @settings['checks'][check['name']]['command'].gsub(/:::(.*?):::/) do
            @settings['client'][$1.to_s].to_s
          end
          EM.system('sh', '-c', command + ' 2>&1') do |output, status|
            @result_queue.publish({'check' => check['name'], 'client' => @settings['client']['name'], 'status' => status.exitstatus, 'output' => output}.to_json)
            @checks_in_progress.delete(check['name'])
          end
        end
      else
        @result_queue.publish({'check' => check['name'], 'client' => @settings['client']['name'], 'status' => 3, 'output' => 'Unknown check'}.to_json)
      end
    end
  end
end
