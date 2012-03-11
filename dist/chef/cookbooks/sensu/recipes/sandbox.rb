#
# Cookbook Name:: sensu
# Recipe:: sandbox
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

include_recipe "git::default"

gem_package "bundler"

directory File.join(node.sensu.sandbox.directory, "shared/vendor") do
  recursive true
end

execute "bundle" do
  command "bundle install --path vendor --without development test"
  cwd File.join(node.sensu.sandbox.directory, "current")
  action :nothing
  notifies :run, 'execute[gem_update]', :immediate
end

deploy_revision "sensu" do
  deploy_to node.sensu.sandbox.directory
  repository "git://github.com/sonian/sensu.git"
  revision "v#{node.sensu.version}"
  purge_before_symlink Array.new
  create_dirs_before_symlink Array.new
  symlink_before_migrate Hash.new
  symlinks ({"vendor" => "vendor"})
  action File.exists?(File.join(node.sensu.sandbox.directory, "current")) ? :deploy : :force_deploy
  notifies :run, 'execute[bundle]', :immediate
end

node.set.sensu.bin_path = File.join(node.sensu.sandbox.directory, "current/bin")
