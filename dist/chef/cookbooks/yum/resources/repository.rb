#
# Cookbook Name:: yum
# Resource:: repository
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

actions :add, :remove

#name of the repo, used for .repo filename
attribute :repo_name, :kind_of => String, :name_attribute => true
attribute :description, :kind_of => String #long description
attribute :url, :kind_of => String
attribute :mirrorlist, :default => false
attribute :key, :kind_of => String, :default => nil
attribute :enabled, :default => 1
attribute :type, :kind_of => String, :default => nil
attribute :failovermethod, :kind_of => String, :default => nil
attribute :bootstrapurl, :kind_of => String, :default => nil
