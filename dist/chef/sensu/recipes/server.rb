#
# Cookbook Name:: sensu
# Recipe:: server
#
# Copyright 2011, Sonian Inc.
#
# All rights reserved - Do Not Redistribute
#

include_recipe "rabbitmq"
include_recipe "redis::server"

directory "/etc/rabbitmq/ssl"

ssl = data_bag_item("sensu", "ssl")

%w{
  cacert
  cert
  key
}.each do |file|
  file "/etc/rabbitmq/ssl/#{file}.pem" do
    content ssl["server"][file]
    mode 0644
  end
end

template "/etc/rabbitmq/rabbitmq.config" do
  mode 0644
  notifies :restart, resources(:service => "rabbitmq-server")
end

rabbitmq_vhost node.sensu.rabbitmq.vhost do
  action :create
end

rabbitmq_user node.sensu.rabbitmq.user do
  action :create
  password node.sensu.rabbitmq.password
  permissions({node.sensu.rabbitmq.vhost => [".*", ".*", ".*"]})
end

include_recipe "sensu::default"

template "/etc/init/sensu-server.conf" do
  source "upstart.erb"
  variables :service => "server"
  mode 0644
end

cookbook_file "/etc/sensu/handler" do
  mode 0755
end

service "sensu-server" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  subscribes :restart, resources(:file => "/etc/sensu/config.json"), :delayed
end
