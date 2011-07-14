#
# Cookbook Name:: sa-monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

databag = data_bag('sa-monitoring')

template '/etc/sa-monitoring/config.json' do
  mode 0600
  variables(
    'roles' => search(:role, '*:*'),
    'checks' => databag['checks']
  )
end
