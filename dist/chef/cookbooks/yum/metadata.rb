maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           "0.5.2"
recipe            "yum", "Runs 'yum update' during compile phase"
recipe            "yum::yum", "manages yum configuration"

%w{ redhat centos scientific }.each do |os|
  supports os, ">= 5.0"
end

attribute "yum/exclude",
  :display_name => "yum.conf exclude",
  :description => "List of packages to exclude from updates or installs. This should be a space separated list.  Shell globs using wildcards (eg. * and ?) are allowed.",
  :required => "optional"

attribute "yum/installonlypkgs",
  :display_name => "yum.conf installonlypkgs",
  :description => "List of packages that should only ever be installed, never updated. Kernels in particular fall into this category. Defaults to kernel, kernel-smp, kernel-bigmem, kernel-enterprise, kernel-debug, kernel-unsupported.",
  :required => "optional"
