#
# Cookbook Name:: sensu
# Recipe:: dashboard
#
# Copyright 2011, Sonian Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "sensu::default"

gem_package "thin"

gem_package "sensu-dashboard" do
  version node.sensu.dashboard.version
end

template "/etc/init/sensu-dashboard.conf" do
  source "upstart.erb"
  variables :service => "dashboard"
  mode 0644
end

service "sensu-dashboard" do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  subscribes :restart, resources(:file => "/etc/sensu/config.json"), :delayed
end
