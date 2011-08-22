#
# Cookbook Name:: sensu
# Recipe:: client
#
# Copyright 2011, Sonian Inc.
#
# All rights reserved - Do Not Redistribute
#

include_recipe "sensu::default"

template "/etc/init/sensu-client.conf" do
  source "upstart.erb"
  variables :service => "client"
  mode 0644
end

service "sensu-client" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  subscribes :restart, resources(:file => "/etc/sensu/config.json"), :delayed
end
