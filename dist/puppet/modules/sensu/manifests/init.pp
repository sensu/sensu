class sensu {

  require sensu::dependencies
  include sensu::params

  $user                 = $sensu::params::user
  $log_directory        = $sensu::params::log_directory
  $rabbitmq_host        = $sensu::params::rabbitmq_host
  $rabbitmq_port        = $sensu::params::rabbitmq_port
  $redis_host           = $sensu::params::redis_host
  $redis_port           = $sensu::params::redis_port
  $api_host             = $sensu::params::api_host
  $api_port             = $sensu::params::api_port
  $dashboard_host       = $sensu::params::dashboard_host
  $dashboard_port       = $sensu::params::dashboard_port
  $dashboard_user       = $sensu::params::dashboard_user
  $dashboard_password   = $sensu::params::dashboard_password

  package { 'sensu':
    ensure   => latest,
    provider => gem,
  }

  file { '/etc/sensu':
    ensure  => directory,
  }

  file { '/etc/sensu/plugins':
    ensure  => directory,
    mode    => '0755',
    require => File['/etc/sensu'],
  }

  file { $log_directory:
    ensure  => directory,
    mode    => '0755',
    owner   => $user,
    require => User[$user],
  }

  file { '/etc/sensu/ssl':
    ensure  => directory,
    require => File['/etc/sensu'],
  }

  file { '/etc/sensu/plugins/puppet_agent.rb':
    ensure  => file,
    mode    => '0755',
    source  => 'puppet:///modules/sensu/plugins/puppet_agent.rb',
    require => File['/etc/sensu/plugins'],
  }

  user { $user:
    ensure  => present,
    require => File['/etc/sensu'],
  }

  file { '/etc/sudoers.d/sensu':
    ensure  => file,
    content => template('sensu/sudoers.erb'),
    mode    => '0440',
  }

  file { '/etc/sensu/config.json':
    ensure  => file,
    content => template('sensu/config.json.erb'),
    mode    => '0644',
    require => File['/etc/sensu'],
  }

}
