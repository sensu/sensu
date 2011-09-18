class sensu::api {

  require sensu
  include sensu::params

  $sensu_user = sensu::params::sensu_user
  $service = "api"

  package { "thin":
    provider => gem,
    ensure   => latest,
  }

  file { "/etc/init/sensu-api.conf":
    ensure  => file,
    content => template("sensu/upstart.erb"),
    mode    => 0644,
  }

  service { "sensu-api":
    ensure    => running,
    enable    => true,
    subscribe => File["/etc/sensu/config.json"],
    require   => File["/etc/init/sensu-server.conf"],
  }
}

