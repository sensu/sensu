# Cookbook Name:: erlang
# Recipe:: default
# Author:: Joe Williams <joe@joetify.com>
# Author:: Matt Ray <matt@opscode.com>
#
# Copyright 2008-2009, Joe Williams
# Copyright 2011, Opscode Inc.
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
when "debian", "ubuntu"
  erlpkg = node[:erlang][:gui_tools] ? "erlang" : "erlang-nox"
  package erlpkg
  package "erlang-dev"
when "redhat", "centos", "scientific"
  include_recipe "yum::epel"
  yum_repository "erlang" do
    name "EPELErlangrepo"
    url "http://repos.fedorapeople.org/repos/peter/erlang/epel-5Server/#{node['kernel']['machine']}"
    action :add
  end
  package "erlang"
else
  package "erlang"
end
