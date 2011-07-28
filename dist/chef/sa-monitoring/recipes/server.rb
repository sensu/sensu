#
# Cookbook Name:: sa-monitoring
# Recipe:: server
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "rabbitmq"
include_recipe "redis2"

include_recipe "sa-monitoring::default"

service "sa-monitoring-server" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
end
