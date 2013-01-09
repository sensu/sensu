require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'timeout'
require 'socket'

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

def test_local_tcp_socket(port)
  begin
    timeout(1) do
      socket = TCPSocket.new('localhost', port)
      socket.close
    end
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
    false
  end
end

desc 'Run tests'
task :test do
  puts 'Running tests ...'
  unless test_local_tcp_socket(5672)
    raise('RABBITMQ MUST BE RUNNING!')
  end
  unless test_local_tcp_socket(6379)
    raise('REDIS MUST BE RUNNING!')
  end
  require File.join(File.dirname(__FILE__), 'test', 'helper')
  Dir.glob('test/*_tests.rb').each do |tests|
    require File.join(File.dirname(__FILE__), tests)
  end
end
