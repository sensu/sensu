Description
===========

Sets up iptables to use a script to maintain firewall rules. However
this cookbook may be deprecated or heavily modified in favor of the
general firewall cookbook, see __Roadmap__.

Changes
=======

### v0.10.0:

* [COOK-641] - be able to save output on rhel-family
* [COOK-655] - use a template from other cookbooks

### v0.9.3:

* Current public release.

Roadmap
-------

* [COOK-652] - create a firewall cookbook
* [COOK-688] - create iptables providers for all resources

Requirements
============

## Platform:

* Ubuntu/Debian
* RHEL/CentOS

Recipes
=======

default
-------

The default recipe will install iptables and provides a perl script
(installed in `/usr/sbin/rebuild-iptables`) to manage rebuilding
firewall rules from files dropped off in `/etc/iptables.d`.

Definitions
===========

See __Roadmap__ for plans to replace the definition with LWRPs.

iptables\_rule
--------------

The definition drops off a template in `/etc/iptables.d` after the
`name` parameter. The rule will get added to the local system firewall
through notifying the `rebuild-iptables` script. See __Examples__ below.

Usage
=====

Ensure that the system is set up to use the definition and rebuild
script with `recipe[iptables]`. Then create templates with the
firewall rules in the cookbook where the definition will be used. See
__Examples__.

Examples
--------

To enable port 80, e.g. in an `httpd` cookbook, create the following
template:

    # Port 80 for http
    -A FWR -p tcp -m tcp --dport 80 -j ACCEPT

This would go in the cookbook,
`httpd/templates/default/port_http.erb`. Then to use it in
`recipe[httpd]`:

    iptables_rule "http"

License and Author
==================

Author:: Adam Jacob <adam@opscode.com>
Author:: Joshua Timberman <joshua@opscode.com>

Copyright:: 2008-2011, Opscode, Inc

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
