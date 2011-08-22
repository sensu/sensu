maintainer       "Sonian, Inc."
maintainer_email "chefs@sonian.net"
license          "All rights reserved"
description      "Installs/Configures sensu"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rdoc'))
version          "0.0.1"

# available @ http://community.opscode.com/cookbooks/rabbitmq
depends "rabbitmq"

# available @ http://community.opscode.com/cookbooks/redis-package
depends "redis"
