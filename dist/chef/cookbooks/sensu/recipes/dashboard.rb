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

case node[:platform]
when "ubuntu", "debian"
  template "/etc/init/sensu-dashboard.conf" do
    source "init/sensu-service.conf.erb"
    variables :service => "dashboard", :options => "-l #{node.sensu.log.directory}/sensu.log"
    mode 0644
  end

  service "sensu-dashboard" do
    provider Chef::Provider::Service::Upstart
    action [:enable, :start]
    subscribes :restart, resources(:file => File.join(node.sensu.directory, "config.json"), :gem_package => "sensu-dashboard"), :delayed
  end
when "centos", "redhat"
  template "/etc/init.d/sensu-dashboard" do
    source "init/sensu-service.erb"
    variables :service => "dashboard"
    mode 0755
  end

  service "sensu-dashboard" do
    action [:enable, :start]
    supports :restart => true
    subscribes :restart, resources(:file => File.join(node.sensu.directory, "config.json"), :gem_package => "sensu-dashboard"), :delayed
  end
end
