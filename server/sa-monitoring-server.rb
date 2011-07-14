require 'rubygems'
require 'amqp'
require 'json'

server = 'localhost'
checks = { :fitter_happier => { :roles => ['webserver'] }, :cluster_health => { :roles => ['elasticsearch_ebs'] } }
roles = ['webserver','elasticsearch_ebs']

AMQP.start(:host => server) do
  exchanges = Hash.new
  roles.each do |role|
    exchanges[role] = MQ.new.fanout(role)
  end

  checks.each do |check, settings|
    settings[:roles].each do |role|
      exchanges[role].publish(check.to_json)
    end
  end

  amq = MQ.new
  amq.queue('listener').bind(amq.fanout('results')).subscribe do |msg|
    puts msg
  end
end
