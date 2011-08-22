#
# Cookbook Name:: sensu
# Recipe:: default
#
# Copyright 2011, Sonian Inc.
#
# All rights reserved - Do Not Redistribute
#

package "libssl-dev"

gem_package "sensu" do
  version node.sensu.version
end

directory "/etc/sensu"

user node.sensu.user do
  comment "monitoring user"
  system true
  home "/etc/sensu"
end

template "/etc/sudoers.d/sensu" do
  source "sudoers.erb"
  mode 0440
end

remote_directory "/etc/sensu/plugins" do
  files_mode 0755
end

directory "/etc/sensu/ssl"

ssl = data_bag_item("sensu", "ssl")

file node.sensu.rabbitmq.ssl.cert_chain_file do
  content ssl["client"]["cert"]
  mode 0644
end

file node.sensu.rabbitmq.ssl.private_key_file do
  content ssl["client"]["key"]
  mode 0644
end

file "/etc/sensu/config.json" do
  content Sensu.generate_config(node, data_bag_item("sensu", "config"))
  mode 0644
end

%w{
  nagios-plugins
  nagios-plugins-basic
  nagios-plugins-standard
}.each do |pkg|
  package pkg
end
