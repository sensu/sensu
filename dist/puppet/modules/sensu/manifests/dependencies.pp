class sensu::dependencies {

  include sensu::params

  $packages             = $sensu::params::packages

  case $::operatingsystem {
    'scientific', 'redhat', 'centos': {
      # All packages installed as dependencies
    }

    'debian', 'ubuntu': {

      package { 'thin':
          ensure => latest,
      }

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
