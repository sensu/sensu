maintainer       "Sonian, Inc."
maintainer_email "chefs@sonian.net"
license          "Apache 2.0"
description      "Installs/Configures Sensu"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rdoc'))
version          "0.0.1"

# available @ http://community.opscode.com/cookbooks/rabbitmq
depends "rabbitmq"

# available @ http://community.opscode.com/cookbooks/redis-package
depends "redis"
