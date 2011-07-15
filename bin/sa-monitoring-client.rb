require 'rubygems'
require 'amqp'
require 'json'

config_file = if ENV['development']
  File.dirname(__FILE__) + '/../client.json'
else
  '/etc/sa-monitoring/client.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

AMQP.start(:host => config['rabbitmq']['server'],
           :vhost => config['rabbitmq']['vhost'],
           :username => config['rabbitmq']['username'],
           :password => config['rabbitmq']['password']) do

  amq = MQ.new

  result = amq.fanout('results')

  config['subscriptions'].each do |subscription|

    amq.queue(subscription).bind(amq.fanout(subscription)).subscribe do |check|

      execute_check = proc do
        output = IO.popen(config['checks'][check]['command']).gets
        {
          'output' => output,
          'status' => $?.to_i
        }
      end

      send_result = proc do |check_result|
        result.publish(check_result.to_json)
      end

      EventMachine.defer(execute_check, send_result)
    end
  end
end
