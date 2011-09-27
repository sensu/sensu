require 'bundler/gem_tasks'
require 'rake/testtask'

task :default => 'test'

Rake::TestTask.new do |test|
  test.pattern = 'test/*_test.rb'
end

desc "Build Sensu for Windows"
task :build_windows do
  puts `sh -c 'BUILD=mswin gem build sensu.windows'`
  puts `sh -c 'BUILD=mingw gem build sensu.windows'`
end
