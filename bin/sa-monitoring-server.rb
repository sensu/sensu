require 'rubygems'
require 'amqp'
require 'json'

config_file = if ENV['dev']
  File.dirname(__FILE__) + '/../config.json'
else
  '/etc/sa-monitoring/config.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

module OhaiServer
  def post_init
    puts 'a client connected'
  end

  def receive_data data
    puts data
  end
end

AMQP.start(:host => config['rabbitmq']['server']) do

  amq = MQ.new

  exchanges = Hash.new

  config['checks'].each do |check, info|

    info['subscribers'].each do |exchange|

      if exchanges[exchange].nil?
        exchanges[exchange] = amq.fanout(exchange)
      end

      exchanges[exchange].publish(check)
    end
  end
  
  amq.queue('results').bind(amq.fanout('results')).subscribe do |msg|
    puts msg
  end

  EM::start_server '0.0.0.0', 9000, OhaiServer
end
