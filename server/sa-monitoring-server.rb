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
  exchanges = Hash.new
  config[:roles].each do |role|
    exchanges[role] = MQ.new.fanout(role)
  end

  config[:checks].each do |check, info|
    info[:roles].each do |role|
      exchanges[role].publish(check.to_json)
    end
  end

  amq = MQ.new
  amq.queue('results').bind(amq.fanout('results')).subscribe do |msg|
    puts msg
  end
end
