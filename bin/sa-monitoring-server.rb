require 'rubygems'
require 'amqp'
require 'json'

config_file = if ENV['development']
  File.dirname(__FILE__) + '/../server.json'
else
  '/etc/sa-monitoring/server.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

AMQP.start(:host => config['rabbitmq_server']) do
  amq = MQ.new

  exchanges = Hash.new
  config['exchanges'].each do |exchange|
    exchanges[exchange] = amq.fanout(exchange)
  end

  config['checks'].each do |check, info|
    info['roles'].each do |role|
      exchanges[role].publish(check)
    end
  end
  
  amq.queue('results').bind(amq.fanout('results')).subscribe do |msg|
    puts msg
  end
end
