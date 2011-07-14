require 'rubygems'
require 'amqp'
require 'json'

config_file = if ENV['development']
  File.dirname(__FILE__) + '/../config.json'
else
  '/etc/sa-monitoring/config.json'
end

config = JSON.parse(File.open(config_file, 'r'))

AMQP.start(:host => config[:rabbitmq_server]) do
  amq = MQ.new
  result = MQ.new.fanout('results')
  roles.each do |role|
    amq.queue(role).bind(amq.fanout(role)).subscribe do |msg|
      puts 'received: ' + msg
      result.publish('result for: ' + msg)
    end
  end
end
