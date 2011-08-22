#
# Cookbook Name:: sensu
# Recipe:: api
#
# Copyright 2011, Sonian Inc.
#
# All rights reserved - Do Not Redistribute
#

include_recipe "sensu::default"

gem_package "thin"

template "/etc/init/sensu-api.conf" do
  source "upstart.erb"
  variables :service => "api"
  mode 0644
end

service "sensu-api" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  subscribes :restart, resources(:file => "/etc/sensu/config.json"), :delayed
end
