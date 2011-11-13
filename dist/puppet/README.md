Provisioning Sensu with Puppet
===

This directory contains a Vagrantfile and a 
Puppet module for installing Sensu.

It currently works on Ubuntu only and has been tested 
on all releases after Lucid.

The Puppet module is divided into components.

- Server
- Client
- API
- Worker
- Dashboard

Each can be installed by themselves or in combination. I recommend
always installing the client component on all hosts.

Specify the classes required for each component:

    include sensu::server
    include sensu::client
    include sensu::api
    include sensu::worker
    include sensu::dashboard


