#
# Cookbook Name:: sa_monitoring
# Recipe:: default
#
# Copyright 2011, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

gem_package "sa-monitoring" do
  version node.sa_monitoring.version
end

directory "/etc/sa-monitoring"

remote_directory "/etc/sa-monitoring/plugins" do
  files_mode 0755
end

directory "/etc/sa-monitoring/ssl"

ssl = data_bag_item("sa_monitoring", "ssl")

%w{
  cert
  key
}.each do |file|
  file "/etc/sa-monitoring/ssl/#{file}.pem" do
    content ssl["client"][file]
    mode 0644
  end
end

file "/etc/sa-monitoring/config.json" do
  content SAM.generate_config(node, data_bag_item("sa_monitoring", "config"))
  mode 0644
end

%w{
  server
  api
  client
}.each do |service|
  template "/etc/init/sa-monitoring-#{service}.conf" do
    source "upstart.erb"
    variables :service => service
    mode 0644
  end
end

%w{
  nagios-plugins
  nagios-plugins-basic
  nagios-plugins-standard
}.each do |pkg|
  package pkg
end
