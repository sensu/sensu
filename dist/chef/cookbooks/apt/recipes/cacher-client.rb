#
# Cookbook Name:: apt
# Recipe:: cacher-client
#
# Copyright 2011, Opscode, Inc.
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

#remove Acquire::http::Proxy lines from /etc/apt/apt.conf since we use 01proxy
#these are leftover from preseed installs
execute "Remove proxy from /etc/apt/apt.conf" do
  command "sed --in-place '/^Acquire::http::Proxy/d' /etc/apt/apt.conf"
  only_if "grep Acquire::http::Proxy /etc/apt/apt.conf"
end

servers = search(:node, 'recipes:apt\:\:cacher') || []
if servers.length > 0
  Chef::Log.info("apt-cacher server found on #{servers[0]}.")
  proxy = "Acquire::http::Proxy \"http://#{servers[0].ipaddress}:3142\";\n"
  file "/etc/apt/apt.conf.d/01proxy" do
    owner "root"
    group "root"
    mode "0644"
    content proxy
    action :create
  end
else
  Chef::Log.info("No apt-cacher server found.")
  file "/etc/apt/apt.conf.d/01proxy" do
    action :delete
    only_if {File.exists?("/etc/apt/apt.conf.d/01proxy")}
  end
end
