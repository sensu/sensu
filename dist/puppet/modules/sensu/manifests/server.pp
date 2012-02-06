class sensu::server {

  require sensu
  include sensu::params

  $user          = $sensu::params::user
  $log_directory = $sensu::params::log_directory
  $options       = "-l $log_directory/sensu.log"
  $service       = 'server'

  package { [ 'rabbitmq-server', $sensu::params::redis_package ]:
    ensure => latest,
  }

  file { '/etc/rabbitmq/ssl':
    ensure  => directory,
    mode    => '0755',
    require => Package['rabbitmq-server'],
  }

  file { '/etc/rabbitmq/ssl/cacert.pem':
    ensure  => file,
    source  => 'puppet:///modules/sensu/cacert.pem',
    mode    => '0644',
    require => File['/etc/rabbitmq/ssl'],
  }

  file { '/etc/rabbitmq/ssl/cert.pem':
    ensure  => file,
    source  => 'puppet:///modules/sensu/cert.pem',
    mode    => '0644',
    require => File['/etc/rabbitmq/ssl'],
  }

  file { '/etc/rabbitmq/ssl/key.pem':
    ensure  => file,
    source  => 'puppet:///modules/sensu/key.pem',
    mode    => '0644',
    require => File['/etc/rabbitmq/ssl'],
  }

  file { '/etc/sensu/handlers':
    ensure => directory,
    mode   => '0755',
  }

  file { '/etc/sensu/handlers/default':
    ensure  => file,
    mode    => '0755',
    source  => 'puppet:///modules/sensu/handlers/default',
    require => File['/etc/sensu/handlers'],
  }

  case $::operatingsystem {
    'scientific', 'redhat', 'centos': {
      $server_require = [ Service['rabbitmq-server'], Service[$sensu::params::redis_package] ]
      $server_provider = 'redhat'
    }

    'debian', 'ubuntu': {
      $server_require = [ Service['rabbitmq-server'], Service[$sensu::params::redis_package],
        File['/etc/init/sensu-server.conf'], File["/usr/bin/sensu-${service}"] ]
      $server_provider = 'upstart'

      file { '/etc/init/sensu-server.conf':
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

  service { 'sensu-server':
    ensure    => running,
    enable    => true,
    provider  => $server_provider,
    subscribe => File['/etc/sensu/config.json'],
    require   => $server_require,
  }

  service { [ 'rabbitmq-server', $sensu::params::redis_package ]:
    ensure  => running,
    enable  => true,
    require => [ Package['rabbitmq-server'], Package[$sensu::params::redis_package] ],
  }
}
