#
# Cookbook Name:: runit
# Recipe:: default
#
# Copyright 2008-2010, Opscode, Inc.
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

case node[:platform]
when "debian","ubuntu", "gentoo"
  execute "start-runsvdir" do
    command value_for_platform(
      "debian" => { "default" => "runsvdir-start" },
      "ubuntu" => { "default" => "start runsvdir" },
      "gentoo" => { "default" => "/etc/init.d/runit-start start" }
    )
    action :nothing
  end

  execute "runit-hup-init" do
    command "telinit q"
    only_if "grep ^SV /etc/inittab"
    action :nothing
  end

  if platform? "gentoo"
    template "/etc/init.d/runit-start" do
      source "runit-start.sh.erb"
      mode 0755
    end
  end

  package "runit" do
    action :install
    if platform?("ubuntu", "debian")
      response_file "runit.seed"
    end
    notifies value_for_platform(
      "debian" => { "4.0" => :run, "default" => :nothing  },
      "ubuntu" => {
        "default" => :nothing,
        "9.04" => :run,
        "8.10" => :run,
        "8.04" => :run },
      "gentoo" => { "default" => :run }
    ), resources(:execute => "start-runsvdir"), :immediately
    notifies value_for_platform(
      "debian" => { "squeeze/sid" => :run, "default" => :nothing },
      "default" => :nothing
    ), resources(:execute => "runit-hup-init"), :immediately
  end

  if node[:platform] =~ /ubuntu/i && node[:platform_version].to_f <= 8.04
    cookbook_file "/etc/event.d/runsvdir" do
      source "runsvdir"
      mode 0644
      notifies :run, resources(:execute => "start-runsvdir"), :immediately
      only_if do ::File.directory?("/etc/event.d") end
    end
  end
end
