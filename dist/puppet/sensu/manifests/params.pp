class sensu::params {

  $sensu_version = "0.8.0"
  $sensu_user = "sensu"
  $sensu_packages = [ "libssl-dev", "nagios-plugins", "nagios-plugins-basic", "nagios-plugins-standard" ]
  $sensu_rabbitmq_host = "localhost"
  $sensu_rabbitmq_port = 5671

}
