Description
===========

This cookbook includes recipes to execute apt-get update to ensure the local APT package cache is up to date or manage apt-cacher and cacher clients. It also includes a LWRP for managing APT repositories in /etc/apt/sources.list.d.

Recipes
=======

default
-------

This recipe installs the `update-notifier-common` package to provide the timestamp file used to only run `apt-get update` if the cache is less than one day old.

This recipe should appear first in the run list of Debian or Ubuntu nodes to ensure that the package cache is up to date before managing any `package` resources with Chef.

This recipe also sets up a local cache directory for preseeding packages.

cacher
------

Installs the apt-cacher package and service so the system can provide APT caching. You can check the usage report at http://{hostname}:3142/report. The cacher recipe includes the `cacher-client` recipe, so it helps seed itself.

cacher-client
-------------
Configures the node to use the apt-cacher server as a client.

Resources/Providers
===================

This LWRP provides an easy way to manage additional APT repositories. Adding a new repository will notify running the `execute[apt-get-update]` resource.

# Actions

- :add: creates a repository file and builds the repository listing
- :remove: removes the repository file

# Attribute Parameters

- repo_name: name attribute. The name of the channel to discover
- uri: the base of the Debian distribution
- distribution: this is usually your release's codename...ie something like `karmic`, `lucid` or `maverick`
- components: package groupings..when it doubt use `main`
- deb_src: whether or not to add the repository as a source repo as well
- key_server: the GPG keyserver where the key for the repo should be retrieved
- key: if a `key_server` is provided, this is assumed to be the fingerprint, otherwise it is the URI to the GPG key for the repo

# Examples

    # add the Zenoss repo
    apt_repository "zenoss" do
      uri "http://dev.zenoss.org/deb"
      components ["main","stable"]
      action :add
    end
    
    # add the Nginx PPA; grab key from keyserver
    apt_repository "nginx-php" do
      uri "http://ppa.launchpad.net/nginx/php5/ubuntu"
      distribution node['lsb']['codename']
      components ["main"]
      keyserver "keyserver.ubuntu.com"
      key "C300EE8C"
      action :add
    end
    
    # add the Cloudkick Repo
    apt_repository "cloudkick" do
      uri "http://packages.cloudkick.com/ubuntu"
      distribution node['lsb']['codename']
      components ["main"]
      key "http://packages.cloudkick.com/cloudkick.packages.key"
      action :add
    end
    
    # remove Zenoss repo
    apt_repository "zenoss" do
      action :remove
    end
    
Usage
=====

Put `recipe[apt]` first in the run list. If you have other recipes that you want to use to configure how apt behaves, like new sources, notify the execute resource to run, e.g.:

    template "/etc/apt/sources.list.d/my_apt_sources.list" do
      notifies :run, resources(:execute => "apt-get update"), :immediately
    end

The above will run during execution phase since it is a normal template resource, and should appear before other package resources that need the sources in the template.

Put `recipe[apt::cacher]` in the run_list for a server to provide APT caching and add `recipe[apt::cacher-client]` on the rest of the Debian-based nodes to take advantage of the caching server.

Changes
=======

## v1.2.0:

* COOK-136: Limit apt-get update to one run per day unless notified.
* COOK-471: ignore failure on apt-get update
* COOK-533: add support for deb and `deb_src` repos with `apt_repository`

License and Author
==================

Author:: Joshua Timberman (<joshua@opscode.com>)
Author:: Matt Ray (<matt@opscode.com>)
Author:: Seth Chisamore (<schisamo@opscode.com>)

Copyright 2009-2011 Opscode, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

