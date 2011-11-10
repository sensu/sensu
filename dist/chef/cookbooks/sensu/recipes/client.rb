#
# Cookbook Name:: sensu
# Recipe:: client
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

unless Sensu.is_windows(node)
  template "/etc/init/sensu-client.conf" do
    source "upstart.erb"
    variables :service => "client", :options => "-l #{node.sensu.log.directory}/sensu.log"
    mode 0644
  end

  service "sensu-client" do
    provider Chef::Provider::Service::Upstart
    action [:enable, :start]
    subscribes :restart, resources(:file => File.join(node.sensu.directory, "config.json"), :gem_package => "sensu"), :delayed
  end
end
