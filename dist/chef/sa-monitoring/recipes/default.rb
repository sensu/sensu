#
# Cookbook Name:: sa-monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

gem_package "sa-monitoring"
  version node.sa_monitoring.version
end

directory "/etc/sa-monitoring"

databag = data_bag_item('sa_monitoring', 'config')

file '/etc/sa-monitoring/config.json' do
  content SAM.generate_config(node, databag)
  mode 0644
end

%w{server api client}.each do |service|
  template "/etc/init/sa-monitoring-#{service}.conf" do
    source "upstart.erb"
    variables :service => service
    mode 0644
  end
end
