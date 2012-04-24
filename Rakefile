require 'bundler/gem_tasks'
require 'timeout'
require 'socket'

task :default => 'test'

def test_local_tcp_socket(port)
  begin
    timeout(1) do
      socket = TCPSocket.new('localhost', port)
      socket.close
    end
    true
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    false
  end
end

desc "Run tests"
task :test do
  puts "Running tests ..."
  unless test_local_tcp_socket(5672)
    raise("RABBITMQ MUST BE RUNNING!")
  end
  unless test_local_tcp_socket(6379)
    raise("REDIS MUST BE RUNNING!")
  end
  require File.join(File.dirname(__FILE__), 'test', 'helper')
  Dir['test/*_tests.rb'].each do |test|
    require File.join(File.dirname(__FILE__), test)
  end
end
