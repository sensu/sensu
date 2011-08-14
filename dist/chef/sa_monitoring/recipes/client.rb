#
# Cookbook Name:: sa_monitoring
# Recipe:: client
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

include_recipe "sa_monitoring::default"

template "/etc/init/sa-monitoring-client.conf" do
  source "upstart.erb"
  variables :service => "client"
  mode 0644
end

service "sa-monitoring-client" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  subscribes :restart, resources(:file => "/etc/sa-monitoring/config.json"), :delayed
end
