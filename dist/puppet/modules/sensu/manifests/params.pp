class sensu::params {

  $user               = 'sensu'
  $packages           = [ 'libssl-dev', 'nagios-plugins', 'nagios-plugins-basic', 'nagios-plugins-standard' ]
  $log_directory      = '/var/log/sensu'
  $rabbitmq_host      = '192.168.0.115'
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
  $sensu_package      = $::operatingsystem ? {
    /(scientific|centos|redhat)/  => 'rubygem-sensu',
    /(ubuntu|debian)/             => 'sensu',
    default                       => 'sensu',
  }
  $sensu_dash_package = $::operatingsystem ? {
    /(scientific|centos|redhat)/  => 'rubygem-sensu-dashboard',
    /(ubuntu|debian)/             => 'sensu-dashboard',
    default                       => 'sensu-dashboard',
  }
  $sensu_provider     = $::operatingsystem ? {
    /(scientific|centos|redhat)/  => 'yum',
    /(ubuntu|debian)/             => 'gem',
    default                       => 'gem',
  }
  $redis_package      = $::operatingsystem ? {
    /(scientific|centos|redhat)/  => 'redis',
    /(ubuntu|debian)/             => 'redis-server',
    default                       => 'redis-server',
  }
}
