class sensu::params {

  $user               = 'sensu'
  $packages           = [ 'libssl-dev', 'nagios-plugins', 'nagios-plugins-basic', 'nagios-plugins-standard' ]
  $log_directory      = '/var/log/sensu'
  $rabbitmq_host      = 'localhost'
  $rabbitmq_port      = 5672
  $rabbitmq_user      = 'sensu'
  $rabbitmq_password  = 'password'
  $rabbitmq_vhost     = '/sensu'
  $redis_host         = 'localhost'
  $redis_port         = 6379
  $api_host           = 'localhost'
  $api_port           = 4567
  $dashboard_host     = 'localhost'
  $dashboard_port     = 8080
  $dashboard_user     = 'admin'
  $dashboard_password = 'secret'
}
