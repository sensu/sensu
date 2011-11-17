require 'bundler/gem_tasks'

task :default => 'test'

desc "Run tests"
task :test do
  require File.join(File.dirname(__FILE__), 'test', 'helper')
  Dir['test/*_test.rb'].each do |test|
    require File.join(File.dirname(__FILE__), test)
  end
end
