maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
description       "Installs git and/or sets up a Git server daemon"
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           "0.10.0"
recipe            "git", "Installs git"
recipe            "git::server", "Sets up a runit_service for git daemon"

%w{ ubuntu debian arch centos }.each do |os|
  supports os
end

%w{ runit yum }.each do |cb|
  depends cb
end
