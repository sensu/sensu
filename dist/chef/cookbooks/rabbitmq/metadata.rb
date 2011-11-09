maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
description       "Installs and configures RabbitMQ server"
version           "1.3"
recipe            "rabbitmq", "Install and configure RabbitMQ"
recipe            "rabbitmq::cluster", "Set up RabbitMQ clustering."
depends           "apt", ">= 1.1"
depends           "yum", ">= 0.5.0"
depends           "erlang", ">= 0.9"

%w{ubuntu debian redhat centos scientific}.each do |os|
  supports os
end

attribute "rabbitmq",
  :display_name => "RabbitMQ",
  :description => "Hash of RabbitMQ attributes",
  :type => "hash"

attribute "rabbitmq/nodename",
  :display_name => "RabbitMQ Erlang node name",
  :description => "The Erlang node name for this server.",
  :default => "node[:hostname]"
    
attribute "rabbitmq/address",
  :display_name => "RabbitMQ server IP address",
  :description => "IP address to bind."

attribute "rabbitmq/port",
  :display_name => "RabbitMQ server port",
  :description => "TCP port to bind."

attribute "rabbitmq/config",
  :display_name => "RabbitMQ config file to load",
  :description => "Path to the rabbitmq.config file, if any."

attribute "rabbitmq/logdir",
  :display_name => "RabbitMQ log directory",
  :description => "Path to the directory for log files."

attribute "rabbitmq/mnesiadir",
  :display_name => "RabbitMQ Mnesia database directory",
  :description => "Path to the directory for Mnesia database files."

attribute "rabbitmq/cluster",
  :display_name => "RabbitMQ clustering",
  :description => "Whether to activate clustering.",
  :default => "no"
  
attribute "rabbitmq/cluster_config",
  :display_name => "RabbitMQ clustering configuration file",
  :description => "Path to the clustering configuration file, if cluster is yes.",
  :default => "/etc/rabbitmq/rabbitmq_cluster.config"

attribute "rabbitmq/cluster_disk_nodes",
  :display_name => "RabbitMQ cluster disk nodes",
  :description => "Array of member Erlang nodenames for the disk-based storage nodes in the cluster.",
  :default => [],
  :type => "array"

attribute "rabbitmq/erlang_cookie",
  :display_name => "RabbitMQ Erlang cookie",
  :description => "Access cookie for clustering nodes.  There is no default."
  
