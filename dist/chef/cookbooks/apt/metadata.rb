maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
description       "Configures apt and apt services and an LWRP for managing apt repositories"
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           "1.2.0"
recipe            "apt", "Runs apt-get update during compile phase and sets up preseed directories"
recipe            "apt::cacher", "Set up an APT cache"
recipe            "apt::cacher-client", "Client for the apt::cacher server"

%w{ ubuntu debian }.each do |os|
  supports os
end
