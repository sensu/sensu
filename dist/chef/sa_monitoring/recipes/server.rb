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

include_recipe "sa_monitoring::default"

cookbook_file "/etc/sa-monitoring/handler" do
  mode 0755
end

service "sa-monitoring-server" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
end
