require 'rubygems'
require 'amqp'
require 'json'
require 'uuidtools'
require 'em-redis'

config_file = if ENV['dev']
  File.dirname(__FILE__) + '/../config.json'
else
  '/etc/sa-monitoring/config.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

AMQP.start(:host => config['rabbitmq']['server']) do

  amq = MQ.new

  exchanges = Hash.new

  amq.queue('results').subscribe do |msg|
    puts msg
  end

  amq.queue('checks').subscribe do |check|
    check = JSON.parse(check)

    check_id = UUIDTools::UUID.random_create.to_s
    check_msg = {
      :name => check['name'],
      :id => check_id
    }.to_json

    check['subscribers'].each do |exchange|

      if exchanges[exchange].nil?
        exchanges[exchange] = amq.fanout(exchange)
      end

      exchanges[exchange].publish(check_msg)
    end
  end

  work = AMQP::Exchange.default

  config['checks'].each do |name, info|
    work.publish({'name' => name, 'subscribers' => info['subscribers']}.to_json, :routing_key => 'checks')
  end

  module OhaiServer
    redis = EM::Protocols::Redis.connect
    def receive_data data
      puts data
      redis.set("client1", "bits")
    end
  end

  EM::start_server '0.0.0.0', 9000, OhaiServer
end
