maintainer       "Sonian, Inc."
maintainer_email "chefs@sonian.net"
license          "Apache 2.0"
description      "Installs/Configures Sensu"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rdoc'))
version          "0.0.4"

# available @ http://community.opscode.com/cookbooks/rabbitmq
depends "rabbitmq_sensu"

# available @ http://community.opscode.com/cookbooks/redis-package
depends "redis"

# available @ http://community.opscode.com/cookbooks/apt
depends "apt"

#
depends "yum"

%w{ubuntu debian redhat centos}.each do |os|
  supports os
end
