#
# Cookbook Name:: sa-monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

directory "/etc/sa-monitoring"

databag = data_bag_item('sa_monitoring', 'config')

file '/etc/sa-monitoring/config.json' do
  content SAM.generate_config(node, databag)
  mode 0644
end

%w{server api client}.each do |service|
  cookbook_file "/etc/init/sa-monitoring-#{service}.conf" do
    mode 0644
  end
end
