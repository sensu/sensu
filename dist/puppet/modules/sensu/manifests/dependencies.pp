class sensu::dependencies {

  include sensu::params

  $packages             = $sensu::params::packages

  package { 'thin':
    ensure => latest,
  }

  case $operatingsystem {
    'redhat', 'centos': {

      fail('Platform not supported by Sensu module. Patches welcomed.')

    }
    'debian', 'ubuntu': {

      package { $packages:
        ensure  => latest,
      }

      exec { 'apt-update':
        command => '/usr/bin/apt-get update',
        before  => Package[$packages],
      }
    }
    default: {
      fail('Platform not supported by Sensu module. Patches welcomed.')
    }
  }
}
