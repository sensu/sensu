#
# Cookbook Name:: yum
# Attributes:: default 
#
# Copyright 2011, Eric G. Wolfe 
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

# Example: override.yum.exclude = "kernel* compat-glibc*"
default[:yum][:exclude]
default[:yum][:installonlypkgs]

default['yum']['epel_release'] = case node['platform_version'].to_i
                                  when 6
                                    "6-5"
                                  when 5
                                    "5-4"
                                  when 4
                                    "4-10"
                                  end
default['yum']['ius_release'] = '1.0-8'
