class sensu::server {

  require sensu
  include sensu::params

  $sensu_rabbitmq_port = $sensu::params::sensu_rabbitmq_port
  $sensu_user = $sensu::params::sensu_user

  $service = "server"

  package { [ "rabbitmq-server", "redis-server" ]:
    ensure => latest,
  }

  file { "/etc/rabbitmq/ssl":
    ensure  => directory,
    mode    => 0755,
    require => Package["rabbitmq-server"],
  }

  file { "/etc/rabbitmq/ssl/cacert.pem":
    ensure  => file,
    source  => "puppet:///modules/sensu/cacert.pem",
    mode    => 0644,
    require => File["/etc/rabbitmq/ssl"],
  }

  file { "/etc/rabbitmq/ssl/cert.pem":
    ensure  => file,
    source  => "puppet:///modules/sensu/cert.pem",
    mode    => 0644,
    require => File["/etc/rabbitmq/ssl"],
  }

  file { "/etc/rabbitmq/ssl/key.pem":
    ensure  => file,
    source  => "puppet:///modules/sensu/key.pem",
    mode    => 0644,
    require => File["/etc/rabbitmq/ssl"],
  }

  file { "/etc/rabbitmq/rabbitmq.config":
    ensure  => file,
    content => template("sensu/rabbitmq.config.erb"),
    mode    => 0644,
    require => Package["rabbitmq-server"],
    notify  => Service["rabbitmq-server"],
  }

  file { "/etc/sensu/handlers":
    ensure => directory,
    mode   => 0755,
  }

  file { "/etc/sensu/handlers/default":
    ensure  => file,
    mode    => 0755,
    source  => "puppet:///modules/sensu/handlers/default",
    require => File["/etc/sensu/handlers"],
  }

  file { "/etc/init/sensu-server.conf":
    ensure  => file,
    content => template("sensu/upstart.erb"),
    mode    => 0644,
  }

  service { "sensu-server":
    ensure    => running,
    enable    => true,
    subscribe => File["/etc/sensu/config.json"],
    require   => File["/etc/init/sensu-server.conf"],
  }

  service { [ "rabbitmq-server", "redis-server" ]:
    ensure  => running,
    enable  => true,
    require => [ Package["rabbitmq-server"], Package["redis-server"] ],
  }
}
