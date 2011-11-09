#
# Cookbook Name:: rabbitmq
# Recipe:: cluster
#
# Copyright 2009, Benjamin Black
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
include_recipe "rabbitmq::default"

template "/var/lib/rabbitmq/.erlang.cookie" do
  source "doterlang.cookie.erb"
  owner "rabbitmq"
  group "rabbitmq"
  mode 0400
end

template "/etc/rabbitmq/rabbitmq_cluster.config" do
  source "rabbitmq_cluster.config.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, resources(:service => "rabbitmq-server")
end

