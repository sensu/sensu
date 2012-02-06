class sensu::dashboard {

    require sensu
    include sensu::params

    $service = 'dashboard'
    $user    = $sensu::params::user
    $options = ''

    package { $sensu::params::sensu_dash_package:
      ensure   => latest,
      provider => $sensu::params::sensu_provider,
    }

    case $::operatingsystem {
      'scientific', 'redhat', 'centos': {
        $dash_require = Package[$sensu::params::sensu_dash_package]
        $dash_provider = 'redhat'
      }

      'debian', 'ubuntu': {
        $dash_require = [ Package[$sensu::params::sensu_dash_package],
          File["/usr/bin/sensu-${service}"], File['/etc/init/sensu-dashboard.conf'] ]
        $dash_provider = 'upstart'

        file { '/etc/init/sensu-dashboard.conf':
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

    service { 'sensu-dashboard':
      ensure    => running,
      enable    => true,
      provider  => $dash_provider,
      subscribe => File['/etc/sensu/config.json'],
      require   => $dash_require;
    }
}
