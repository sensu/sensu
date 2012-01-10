#
# Cookbook Name:: iptables
# Definition:: iptables_rule
#
# Copyright 2008-2009, Opscode, Inc.
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

define :iptables_rule, :enable => true, :source => nil, :variables => {}, :cookbook => nil do
  template_source = params[:source] ? params[:source] : "#{params[:name]}.erb"
  
  template "/etc/iptables.d/#{params[:name]}" do
    source template_source
    mode 0644
    cookbook params[:cookbook] if params[:cookbook]
    variables params[:variables]
    backup false
    notifies :run, resources(:execute => "rebuild-iptables")
    if params[:enable]
      action :create
    else
      action :delete
    end
  end
end
