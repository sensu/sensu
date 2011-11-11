class sensu::client {

    require sensu
    include sensu::params

    $service       = 'client'
    $user          = $sensu::params::user
    $log_directory = $sensu::params::log_directory
    $options       = "-l $log_directory/sensu.log"

    file { '/etc/init/sensu-client.conf':
      ensure  => file,
      content => template('sensu/upstart.erb'),
      mode    => '0644',
    }

    exec { "link ${service}":
      command => "/bin/ln -s /var/lib/gems/1.8/bin/sensu-${service} /usr/bin/sensu-${service}",
      creates => "/usr/bin/sensu-${service}",
      require => Package['sensu'],
    }

    service { 'sensu-client':
      ensure    => running,
      enable    => true,
      provider  => upstart,
      subscribe => File['/etc/sensu/config.json'],
      require   => [ Exec["link ${service}"], File['/etc/init/sensu-client.conf'] ],
    }
}
