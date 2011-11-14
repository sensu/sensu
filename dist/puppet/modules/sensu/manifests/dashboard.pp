class sensu::dashboard {

    require sensu
    include sensu::params

    $service = 'dashboard'
    $user    = $sensu::params::user
    $options = ''

    package { 'sensu-dashboard':
      ensure   => latest,
      provider => gem,
    }

    file { '/etc/init/sensu-dashboard.conf':
      ensure  => file,
      content => template('sensu/upstart.erb'),
      mode    => '0644',
    }

    exec { "link ${service}":
      command => "/bin/ln -s /var/lib/gems/1.8/bin/sensu-${service} /usr/bin/sensu-${service}",
      creates => "/usr/bin/sensu-${service}",
      require => Package['sensu'],
    }

    service { 'sensu-dashboard':
      ensure    => running,
      enable    => true,
      provider  => upstart,
      subscribe => File['/etc/sensu/config.json'],
      require   => [ Exec["link ${service}"], File['/etc/init/sensu-dashboard.conf'] ],
    }
}
