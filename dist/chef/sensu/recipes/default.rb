#
# Cookbook Name:: sa_monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

package "libssl-dev"

gem_package "sa-monitoring" do
  version node.sa_monitoring.version
end

directory "/etc/sa-monitoring"

user node.sa_monitoring.user do
  comment "monitoring user"
  system true
  home "/etc/sa-monitoring"
end

template "/etc/sudoers.d/sa-monitoring" do
  source "sudoers.erb"
  mode 0440
end

remote_directory "/etc/sa-monitoring/plugins" do
  files_mode 0755
end

directory "/etc/sa-monitoring/ssl"

ssl = data_bag_item("sa_monitoring", "ssl")

file node.sa_monitoring.rabbitmq.ssl.cert_chain_file do
  content ssl["client"]["cert"]
  mode 0644
end

file node.sa_monitoring.rabbitmq.ssl.private_key_file do
  content ssl["client"]["key"]
  mode 0644
end

file "/etc/sa-monitoring/config.json" do
  content SAM.generate_config(node, data_bag_item("sa_monitoring", "config"))
  mode 0644
end

%w{
  nagios-plugins
  nagios-plugins-basic
  nagios-plugins-standard
}.each do |pkg|
  package pkg
end
