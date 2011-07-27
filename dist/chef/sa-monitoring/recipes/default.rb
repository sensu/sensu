#
# Cookbook Name:: sa-monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

directory "/etc/sa-monitoring"

databag = data_bag('sa-monitoring')

template '/etc/sa-monitoring/config.json' do
  mode 0600
  variables(
    'subscriptions' => node.roles,
    'checks' => databag['checks']
  )
end

%w{server api client}.each do |service|
  cookbook_file "/etc/init/sa-monitoring-#{service}.conf"
end
