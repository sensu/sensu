class sensu::client {

    require sensu
    include sensu::params

    $service = "client"
    $sensu_user = $sensu::params::sensu_user

    file { "/etc/sensu/plugins":
      ensure => directory,
      mode   => 0755,
    }

    file { "/etc/init/sensu-client.conf":
      ensure  => file,
      content => template("sensu/upstart.erb"),
      mode    => 0644,
    }

    service { "sensu-client":
      ensure    => running,
      enable    => true,
      subscribe => File["/etc/sensu/config.json"],
      require   => File["/etc/init/sensu-client.conf"],
    }
}
