require 'rubygems'
require 'bundler'
Bundler.require(:default, :server)

#
# Read the CM created JSON config file
#
config_file = if ENV['dev']
  File.dirname(__FILE__) + '/../config.json'
else
  '/etc/sa-monitoring/config.json'
end

config = JSON.parse(File.open(config_file, 'r').read)

#
# Connect to RabbitMQ
#
AMQP.start(:host => config['rabbitmq']['server']) do

  redis = EM::Protocols::Redis.connect(:host => config['redis']['server'])

  amq = MQ.new

  #
  # Publish critical/warning check results
  #
  amq.queue('results').subscribe do |msg|
    puts msg
  end

  #
  # Send checks out to subscribed clients
  #
  exchanges = Hash.new

  amq.queue('checks').subscribe do |check|
    check = JSON.parse(check)

    check_id = UUIDTools::UUID.random_create.to_s

    redis.set(check_id, check['name'])

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

  #
  # Populate the work queue with checks defined in the JSON config file
  #
  work = amq.direct('')

  config['checks'].each do |name, info|
    work.publish({'name' => name, 'subscribers' => info['subscribers']}.to_json, :routing_key => 'checks')
  end

  #
  # Accept client keep-alives
  #
  class OhaiServer < EM::Connection
    attr_accessor :redis
    
    def receive_data(data)
      @redis.set("client1", data)
    end
  end

  EM::start_server('0.0.0.0', 9000, OhaiServer) do |ohaiserver|
    ohaiserver.redis = redis
  end
end
