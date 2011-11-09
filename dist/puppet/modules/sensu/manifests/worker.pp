class sensu::worker {

  require sensu
  include sensu::params

  $sensu_user = sensu::params::sensu_user
  $service = "server"
  $options = "-w"

  file { "/etc/init/sensu-worker.conf":
    ensure  => file,
    content => template("sensu/upstart.erb"),
    mode    => 0644,
  }

  service { "sensu-worker":
    ensure    => running,
    enable    => true,
    subscribe => File["/etc/sensu/config.json"],
    require   => File["/etc/init/sensu-worker.conf"],
  }
}

