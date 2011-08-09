#
# Cookbook Name:: sa_monitoring
# Recipe:: server
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "rabbitmq"
include_recipe "redis::server"

rabbitmq_vhost node.sa_monitoring.rabbitmq.vhost do
  action :create
end

rabbitmq_user node.sa_monitoring.rabbitmq.user do
  action :create
  password node.sa_monitoring.rabbitmq.password
  permissions({node.sa_monitoring.rabbitmq.vhost => [".*", ".*", ".*"]})
end

include_recipe "sa_monitoring::default"

cookbook_file "/etc/sa-monitoring/handler" do
  mode 0755
end

service "sa-monitoring-server" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
end
