#
# Cookbook Name:: sensu
# Recipe:: server
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

include_recipe "erlang"
include_recipe "rabbitmq"
include_recipe "redis::server"

directory "/etc/rabbitmq/ssl"

ssl = data_bag_item("sensu", "ssl")

%w[
  cacert
  cert
  key
].each do |file|
  file "/etc/rabbitmq/ssl/#{file}.pem" do
    content ssl["server"][file]
    mode 0644
  end
end

template "/etc/rabbitmq/rabbitmq.config" do
  mode 0644
  notifies :restart, resources(:service => "rabbitmq-server")
end

rabbitmq_vhost node.sensu.rabbitmq.vhost do
  action :add
end

rabbitmq_user node.sensu.rabbitmq.user do
  password node.sensu.rabbitmq.password
  action :add
end

rabbitmq_user node.sensu.rabbitmq.user do
  vhost node.sensu.rabbitmq.vhost
  permissions "\".*\" \".*\" \".*\""
  action :set_permissions
end

include_recipe "sensu::default"

remote_directory File.join(node.sensu.directory, "handlers") do
  files_mode 0755
end

case node[:platform]
when "ubuntu", "debian"
  template "/etc/init/sensu-server.conf" do
    source "upstart.erb"
    variables :service => "server", :options => "-l #{node.sensu.log.directory}/sensu.log"
    mode 0644
  end

  service "sensu-server" do
    provider Chef::Provider::Service::Upstart
    action [:enable, :start]
    subscribes :restart, resources(:file => File.join(node.sensu.directory, "config.json"), :gem_package => "sensu"), :delayed
  end
when "centos", "redhat"
  template "/etc/init.d/sensu-server" do
    source "init.erb"
    variables :service => "server", :options => "-l #{node.sensu.log.directory}/sensu.log"
    mode 0755
  end

  service "sensu-server" do
    action [:enable, :start]
    subscribes :restart, resources(:file => File.join(node.sensu.directory, "config.json"), :gem_package => "sensu"), :delayed
  end
end
