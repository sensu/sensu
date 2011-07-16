require 'rubygems'
require 'amqp'
require 'json'

config_file = if ENV['dev']
  File.dirname(__FILE__) + '/../config.json'
else
  '/etc/sa-monitoring/config.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

AMQP.start(:host => config['rabbitmq']['server']) do

  amq = MQ.new

  result = AMQP::Exchange.default

  config['client']['subscriptions'].each do |exchange|

    amq.queue(exchange).bind(amq.fanout(exchange)).subscribe do |check_msg|

      check = JSON.parse(check_msg)

      execute_check = proc do
        output = IO.popen(config['checks'][check['name']]['command']).gets
        {
          'output' => output,
          'status' => $?.to_i,
          'id' => check['id']
        }.to_json
      end

      send_result = proc do |check_result|
        result.publish(check_result, :routing_key => 'results')
      end

      EM.defer(execute_check, send_result)
    end
  end

  class OhaiClient < EM::Connection
    def post_init
      send_data 'Ohai'
      close_connection_after_writing
    end
  end

  EM.add_periodic_timer(30) do
    EM.connect(config['workers'].sample, 9000, OhaiClient)
  end
end
