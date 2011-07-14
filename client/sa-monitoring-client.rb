require 'rubygems'
require 'amqp'

server = 'localhost'
roles = ['webserver','elasticsearch_ebs']

AMQP.start(:host => server) do
  amq = MQ.new
  result = MQ.new.fanout('results')
  roles.each do |role|
    amq.queue('listener').bind(amq.fanout(role)).subscribe do |msg|
      puts 'received: ' + msg
      exchange.publish('result for:' + msg)
    end
  end
end
