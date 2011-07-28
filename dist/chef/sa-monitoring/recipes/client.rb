#
# Cookbook Name:: sa-monitoring
# Recipe:: client
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "sa-monitoring::default"

service "sa-monitoring-client" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
end
