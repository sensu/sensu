require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

require File.join(File.dirname(__FILE__), 'lib/sensu/constants')

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task :default => :spec

task :docker do
  puts 'Creating Sensu Core CentOS Docker image ...'

  release = "#{Sensu::VERSION}-1"

  docker_command = "docker build -f docker/Dockerfile.centos"
  docker_command << " -t sensu/sensu-classic:#{release}"
  docker_command << " --build-arg sensu_release=#{release}"
  docker_command << " ."

  system(docker_command)
end
