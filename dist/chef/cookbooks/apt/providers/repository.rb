#
# Cookbook Name:: apt
# Provider:: repository
#
# Copyright 2010-2011, Opscode, Inc.
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

action :add do
  unless ::File.exists?("/etc/apt/sources.list.d/#{new_resource.repo_name}-source.list")
    Chef::Log.info "Adding #{new_resource.repo_name} repository to /etc/apt/sources.list.d/#{new_resource.repo_name}-source.list"
    # add key
    if new_resource.keyserver && new_resource.key
      execute "install-key #{new_resource.key}" do
        command "apt-key adv --keyserver #{new_resource.keyserver} --recv #{new_resource.key}"
        action :nothing
      end.run_action(:run)
    elsif new_resource.key && (new_resource.key =~ /http/)
      key_name = new_resource.key.split(/\//).last
      remote_file "#{Chef::Config[:file_cache_path]}/#{key_name}" do
        source new_resource.key
        mode "0644"
        action :nothing
      end.run_action(:create_if_missing)
      execute "install-key #{key_name}" do
        command "apt-key add #{Chef::Config[:file_cache_path]}/#{key_name}"
        action :nothing
      end.run_action(:run)
    end
    # build our listing
    repository = "deb"
    repository = "deb-src" if new_resource.deb_src
    repository = "# Created by the Chef apt_repository LWRP\n" + repository
    repository += " #{new_resource.uri}"
    repository += " #{new_resource.distribution}"
    new_resource.components.each {|component| repository += " #{component}"}
    # write out the file, replace it if it already exists
    file "/etc/apt/sources.list.d/#{new_resource.repo_name}-source.list" do
      owner "root"
      group "root"
      mode 0644
      content repository + "\n"
      action :nothing
    end.run_action(:create)
    execute "update package index" do
      command "apt-get update"
      ignore_failure true
      action :nothing
    end.run_action(:run)
    new_resource.updated_by_last_action(true)
  end
end

action :remove do
  if ::File.exists?("/etc/apt/sources.list.d/#{new_resource.repo_name}-source.list")
    Chef::Log.info "Removing #{new_resource.repo_name} repository from /etc/apt/sources.list.d/"
    file "/etc/apt/sources.list.d/#{new_resource.repo_name}-source.list" do
      action :delete
    end
    new_resource.updated_by_last_action(true)
  end
end
