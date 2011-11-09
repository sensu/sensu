class sensu::dashboard {

    require sensu
    include sensu::params

    $service = "dashboard"
    $sensu_user = $sensu::params::sensu_user

    package { [ "thin", "sensu-dashboard":
      ensure   => latest,
      provider => gem,
    }

    file { "/etc/init/sensu-dashboard.conf":
      ensure  => file,
      content => template("sensu/upstart.erb"),
      mode    => 0644,
    }

    service { "sensu-dashboard":
      ensure    => running,
      enable    => true,
      subscribe => File["/etc/sensu/config.json"],
      require   => File["/etc/init/sensu-dashboard.conf"],
    }
}
