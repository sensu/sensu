default[:rabbitmq][:nodename]  = node[:hostname]
default[:rabbitmq][:address]  = nil
default[:rabbitmq][:port]  = 5672
default[:rabbitmq][:config] = nil
default[:rabbitmq][:logdir] = nil
default[:rabbitmq][:mnesiadir] = nil
#clustering
default[:rabbitmq][:cluster] = "no"
default[:rabbitmq][:cluster_config] = "/etc/rabbitmq/rabbitmq_cluster.config"
default[:rabbitmq][:cluster_disk_nodes] = []
