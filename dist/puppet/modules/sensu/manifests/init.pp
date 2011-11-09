class sensu {

  include sensu::params
  $packages = $sensu::params::sensu_packages
  $sensu_version = $sensu::params::sensu_version
  $sensu_user = $sensu::params::sensu_user

  package { $packages:
    ensure   => latest,
  }

  package { "sensu":
    provider => gem,
    ensure   => $sensu_version,
  }

  file { "/etc/sensu":
    ensure  => directory,
  }

  file { "/etc/sensu/ssl":
    ensure  => directory,
    require => File["/etc/sensu"],
  }

  user { $sensu_user:
    ensure  => present,
    require => File["/etc/sensu"],
  }

  file { "/etc/sudoers.d/sensu":
    ensure  => file,
    content => template("sensu/sudoers.erb"),
    mode    => 0440,
  }

  file { "/etc/sensu/config.json":
    ensure  => file,
    content => template("sensu/config.json.erb"),
    mode    => 0644,
    require => File["/etc/sensu"],
  }

}
