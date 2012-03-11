class sensu::client {

  require sensu
  include sensu::params

  $service       = 'client'
  $user          = $sensu::params::user
  $log_directory = $sensu::params::log_directory
  $options       = "-l $log_directory/sensu.log"

  case $::operatingsystem {
    'scientific', 'redhat', 'centos': {
      $client_require = Package[$sensu::params::sensu_package]
      $client_provider = 'redhat'
    }

    'debian', 'ubuntu': {
      $client_require = [ Package[$sensu::params::sensu_package],
        File["/usr/bin/sensu-${service}"], File['/etc/init/sensu-client.conf'] ]
      $client_provider = 'upstart'

      file { '/etc/init/sensu-client.conf':
        ensure  => file,
        content => template('sensu/upstart.erb'),
        mode    => '0644',
      }

      file { "/usr/bin/sensu-${service}":
        ensure  => 'link',
        target  => "/var/lib/gems/1.8/bin/sensu-${service}",
        require => Package['sensu'];
      }
    }

    default: {
      fail('Platform not supported by Sensu module. Patches welcomed.')
    }
  }

  service { 'sensu-client':
    ensure    => running,
    enable    => true,
    provider  => $client_provider,
    subscribe => File['/etc/sensu/config.json'],
    require   => $client_require;
  }
}
