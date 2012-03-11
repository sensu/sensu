#
# Cookbook Name:: sensu
# Recipe:: rabbitmq
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

directory "/etc/rabbitmq/ssl"

ssl = data_bag_item("sensu", "ssl")

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
  notifies :restart, 'service[rabbitmq-server]', :immediately
end
