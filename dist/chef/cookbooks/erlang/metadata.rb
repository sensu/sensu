maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
description       "Installs erlang, optionally install GUI tools."
version           "0.9.0"
depends           "yum", ">= 0.5.0"

recipe "erlang", "Installs erlang"

%w{ ubuntu debian redhat centos scientific }.each do |os|
  supports os
end
