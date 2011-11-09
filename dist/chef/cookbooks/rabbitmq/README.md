Description
===========
This is a cookbook for managing RabbitMQ with Chef.  It uses the default settings, but can also be configured via attributes.

Recipes
=======
default
-------
Installs `rabbitmq-server` from RabbitMQ.com's APT repository or the RPM directly (there is no yum repo). The distribution-provided versions were quite old and newer features were needed.

cluster
-------
Configures nodes to be members of a RabbitMQ cluster, but does not actually join them.

Resources/Providers
===================
There are 2 LWRPs for interacting with RabbitMQ.

user
----
Adds and deletes users, fairly simplistic permissions management.

- `:add` adds a `user` with a `password`
- `:delete` deletes a `user`
- `:set_permissions` sets the `permissions` for a `user`, `vhost` is optional
- `:clear_permissions` clears the permissions for a `user`

### Examples
``` ruby
rabbitmq_user "guest" do
  action :delete
end

rabbitmq_user "nova" do
  password "sekret"
  action :add
end

rabbitmq_user "nova" do
  vhost "/nova"
  permissions "\".*\" \".*\" \".*\""
  action :set_permissions
end
```

vhost
-----
Adds and deletes vhosts.

- `:add` adds a `vhost`
- `:delete` deletes a `vhost`

### Example
``` ruby
rabbitmq_vhost "/nova" do
  action :add
end
```

Limitations
===========
It is quite useful as is, but clustering configuration does not currently do the dance to join the cluster members to each other.

The rabbitmq::chef recipe was only used for the chef-server cookbook and has been moved to chef-server::rabbitmq.

License and Author
==================
Author:: Benjamin Black <b@b3k.us>

Author:: Daniel DeLeo <dan@kallistec.com>

Author:: Matt Ray <matt@opscode.com>

Copyright:: 2009-2011 Opscode, Inc

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
