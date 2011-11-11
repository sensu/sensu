class sensu::server {

  require sensu
  include sensu::params

  $user          = $sensu::params::user
  $log_directory = $sensu::params::log_directory
  $options       = "-l $log_directory/sensu.log"
  $service       = 'server'

  package { [ 'rabbitmq-server', 'redis-server' ]:
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

  file { '/etc/init/sensu-server.conf':
    ensure  => file,
    content => template('sensu/upstart.erb'),
    mode    => '0644',
  }

  exec { "link ${service}":
    command => "/bin/ln -s /var/lib/gems/1.8/bin/sensu-${service} /usr/bin/sensu-${service}",
    creates => "/usr/bin/sensu-${service}",
    require => Package['sensu'],
  }

  service { 'sensu-server':
    ensure    => running,
    enable    => true,
    provider  => upstart,
    subscribe => File['/etc/sensu/config.json'],
    require   => [ Service['rabbitmq-server'], Service['redis-server'], File['/etc/init/sensu-server.conf'], Exec["link ${service}"] ],
  }

  service { [ 'rabbitmq-server', 'redis-server' ]:
    ensure  => running,
    enable  => true,
    require => [ Package['rabbitmq-server'], Package['redis-server'] ],
  }
}
