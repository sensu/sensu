require 'rbconfig'
if !!(RbConfig::CONFIG['host_os'] =~ /cygwin|mswin|mingw|bccwin|wince|emx/) # windows
  gem 'eventmachine', ENV.fetch("EVENTMACHINE_VERSION" { '= 1.0.3' } rescue abort("Windows requires eventmachine version 1.0.3\n\t#{$!.inspect}")
end
module Sensu
  # A monitoring framework that aims to be simple, malleable, & scalable.
end
