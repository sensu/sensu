#
# Cookbook Name:: sa-monitoring
# Recipe:: api
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "sa-monitoring::default"

service "sa-monitoring-api" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
end
