Sensu module
---

A Puppet module to install Sensu.

To install the client:

    node "sensu-client" {

      include sensu::client

    }

To install the server or API:

   include sensu::server
   include sensu::api

It requires you create/copy in your proposed RabbitMQ CA cert,
certificate and key to files/{cacert.pem,key.pem,cert.pem}

Author
---

James Turnbull <james@lovedthanlost.net>

License
---

Apache 2.0


