#
# Cookbook Name:: sensu
# Recipe:: default
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

node.sensu.rabbitmq.ssl.cert_chain_file = File.join(node.sensu.directory, "ssl", "cert.pem")
node.sensu.rabbitmq.ssl.private_key_file = File.join(node.sensu.directory, "ssl", "key.pem")

include_recipe "apt"
include_recipe "sensu::dependencies"

unless Sensu.is_windows(node)
  package "libssl-dev"
end

unless Sensu.is_windows(node)
  package "build-essential"
end

gem_package "sensu" do
  version node.sensu.version
end

directory node.sensu.directory do
  recursive true
end

user node.sensu.user do
  comment "monitoring user"
  system true
  home node.sensu.directory
end

directory node.sensu.log.directory do
  recursive true
  owner node.sensu.user
  mode 0755
end

unless Sensu.is_windows(node)
  template "/etc/sudoers.d/sensu" do
    source "sudoers.erb"
    mode 0440
  end
end

remote_directory File.join(node.sensu.directory, "plugins") do
  files_mode 0755
end

directory File.join(node.sensu.directory, "ssl")

ssl = data_bag_item("sensu", "ssl")

file node.sensu.rabbitmq.ssl.cert_chain_file do
  content ssl["client"]["cert"]
  mode 0644
end

file node.sensu.rabbitmq.ssl.private_key_file do
  content ssl["client"]["key"]
  mode 0644
end

file File.join(node.sensu.directory, "config.json") do
  content Sensu.generate_config(node, data_bag_item("sensu", "config"))
  mode 0644
end

unless Sensu.is_windows(node)
  %w[
    nagios-plugins
    nagios-plugins-basic
    nagios-plugins-standard
  ].each do |pkg|
    package pkg
  end
end

