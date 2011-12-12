#
# Cookbook Name:: yum
# Provider:: repository
#
# Copyright 2010, Tippr Inc.
# Copyright 2011, Opscode, Inc..
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

# note that deletion does not remove GPG keys, either from the repo or
# /etc/pki/rpm-gpg; this is a design decision.

action :add do
  unless ::File.exists?("/etc/yum.repos.d/#{new_resource.repo_name}.repo")
    Chef::Log.info "Adding #{new_resource.repo_name} repository to /etc/yum.repos.d/#{new_resource.repo_name}.repo"
    #import the gpg key. If it needs to be downloaded or imported from a cookbook
    #that can be done in the calling recipe
    if new_resource.key then
      yum_key new_resource.key
    end
    #get the metadata
    execute "yum -q makecache" do
      action :nothing
    end
    #write out the file
    template "/etc/yum.repos.d/#{new_resource.repo_name}.repo" do
      cookbook "yum"
      source "repo.erb"
      mode "0644"
      variables({
                  :repo_name => new_resource.repo_name,
                  :description => new_resource.description,
                  :url => new_resource.url,
                  :mirrorlist => new_resource.mirrorlist,
                  :key => new_resource.key,
                  :enabled => new_resource.enabled,
                  :type => new_resource.type,
                  :failovermethod => new_resource.failovermethod,
                  :bootstrapurl => new_resource.bootstrapurl
                })
      notifies :run, resources(:execute => "yum -q makecache"), :immediately
    end
  end
end

action :remove do
  if ::File.exists?("/etc/yum.repos.d/#{new_resource.repo_name}.repo")
    Chef::Log.info "Removing #{new_resource.repo_name} repository from /etc/yum.repos.d/"
    file "/etc/yum.repos.d/#{new_resource.repo_name}.repo" do
      action :delete
    end
    new_resource.updated_by_last_action(true)
  end
end
