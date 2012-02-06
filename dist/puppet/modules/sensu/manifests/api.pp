class sensu::api {

  require sensu
  include sensu::params

  $user          = $sensu::params::user
  $service       = 'api'
  $log_directory = $sensu::params::log_directory
  $options       = "-l $log_directory/sensu.log"

  case $::operatingsystem {
    'scientific', 'redhat', 'centos': {
      $api_require = Package[$sensu::params::sensu_package]
      $api_provider = 'redhat'
    }

    'debian', 'ubuntu': {
      $api_require = [ Package[$sensu::params::sensu_package],
        File["/usr/bin/sensu-${service}"], File['/etc/init/sensu-api.conf'] ]
      $api_provider = 'upstart'

      file { '/etc/init/sensu-api.conf':
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

  service { 'sensu-api':
    ensure    => running,
    enable    => true,
    provider  => $api_provider,
    subscribe => File['/etc/sensu/config.json'],
    require   => $api_require,
  }
}

