Description
===========

Configures various YUM components on Red Hat-like systems.  Includes LWRP for managing repositories and their GPG keys.

Based on the work done by Eric Wolfe and Charles Duffy on the yumrepo cookbook. http://github.com/atomic-penguin/cookbooks/tree/yumrepo/yumrepo

Changes
=======

## v0.5.2:

* [COOK-825] - epel and ius `remote_file` should notify the `rpm_package` to install

## v0.5.0:

* [COOK-675] - add recipe for handling EPEL repository
* [COOK-722] - add recipe for handling IUS repository

## v.0.1.2:

* Remove yum update in default recipe, that doesn't update caches, it updates packages installed.

Requirements
============
RHEL, CentOS or Scientific Linux 5.x or newer. It has not been tested on other platforms or earlier versions. RHEL 6 support is untested (testing and patches are welcome).

Attributes
==========

* `node['yum']['epel_release']` - Set the epel release version based on `node['platform_version']`.
* `node['yum']['ius_release']` - Set the IUS release to install.

Recipes
=======

default
-------
The default recipe runs `yum update` during the Compile Phase of the Chef run to ensure that the system's package cache is updated with the latest. It is recommended that this recipe appear first in a node's run list (directly or through a role) to ensure that when installing packages, Chef will be able to download the latest version available on the remote YUM repository.

yum
---
Manages the configuration of the `/etc/yum.conf` via attributes.

epel
----

Installs the EPEL repository via RPM. Uses the `node['yum']['epel_release']` attribute to select the right version of the repository package to install. Also uses the node's platform version (as an integer) for the major release of EL.

ius
----

Installs the [IUS Community repositories](http://iuscommunity.org/Repos) via RPM. Uses the `node['yum']['ius_release']` attribute to select the right versino of the package to install.

The IUS repository requires EPEL, and the recipe includes `yum::epel` to install this.

Resources/Providers
===================

key
---
This LWRP handles importing GPG keys for YUM repositories. Keys can be imported by the `url` parameter or placed in `/etc/pki/rpm-gpg/` by a recipe and then installed with the LWRP without passing the URL.

# Actions
- :add: installs the GPG key into `/etc/pki/rpm-gpg/`
- :remove: removes the GPG key from `/etc/pki/rpm-gpg/`

# Attribute Parameters

- key: name attribute. The name of the GPG key to install.
- url: if the key needs to be downloaded, the URL providing the download.

# Example

``` ruby
# add the Zenoss GPG key
yum_key "RPM-GPG-KEY-zenoss" do
  url "http://dev.zenoss.com/yum/RPM-GPG-KEY-zenoss"
  action :add
end
    
# remove Zenoss GPG key
yum_key "RPM-GPG-KEY-zenoss" do
  action :remove
end
```

repository
----------
This LWRP provides an easy way to manage additional YUM repositories. GPG keys can be managed with the `key` LWRP.

# Actions

- :add: creates a repository file and builds the repository listing
- :remove: removes the repository file

# Attribute Parameters

- repo_name: name attribute. The name of the channel to discover
- description. The description of the repository
- url: The URL providing the packages
- mirrorlist: Default is `false`,  if `true` the `url` is considered a list of mirrors
- key: Optional, the name of the GPG key file installed by the `key` LWRP.

- enabled: Default is `1`, set to `0` if the repository is disabled.
- type: Optional, alternate type of repository
- failovermethod: Optional, failovermethod
- bootstrapurl: Optional, bootstrapurl

# Example

``` ruby
# add the Zenoss repository
yum_repository "zenoss" do
  name "Zenoss Stable repo"
  url "http://dev.zenoss.com/yum/stable/"
  key "RPM-GPG-KEY-zenoss"
  action :add
end
    
# remove Zenoss repo
yum_repository "zenoss" do
  action :remove
end
```

Usage
=====

Put `recipe[yum]` first in the run list to ensure `yum update` is run before other recipes. You can manage GPG keys either with cookbook_file in a recipe if you want to package it with a cookbook or use the `url` parameter of the `key` LWRP.

License and Author
==================

Author:: Eric G. Wolfe
Author:: Matt Ray (<matt@opscode.com>)
Author:: Joshua Timberman (<joshua@opscode.com>)

Copyright:: 2010 Tippr Inc.
Copyright:: 2011 Eric G. Wolfe
Copyright:: 2011 Opscode, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
