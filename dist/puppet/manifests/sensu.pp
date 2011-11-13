class base {

  include sensu::server
  include sensu::client
  include sensu::dashboard
  include sensu::api

  group { "puppet":
    ensure => present,
  }
}

include base
