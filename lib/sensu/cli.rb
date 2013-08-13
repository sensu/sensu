require 'optparse'

module Sensu
  class CLI
    def self.read(arguments=ARGV)
      options = Hash.new
      optparse = OptionParser.new do |opts|
        opts.on('-h', '--help', 'Display this message') do
          puts opts
          exit
        end
        opts.on('-V', '--version', 'Display version') do
          puts VERSION
          exit
        end
        opts.on('-c', '--config FILE', 'Sensu JSON config FILE') do |file|
          options[:config_file] = file
        end
        opts.on('-d', '--config_dir DIR[,DIR]', 'DIR or comma-delimited DIR list for Sensu JSON config files') do |dir|
          options[:config_dirs] = dir.split(',')
        end
        opts.on('-e', '--extension_dir DIR', 'DIR for Sensu extensions') do |dir|
          options[:extension_dir] = dir
        end
        opts.on('-l', '--log FILE', 'Log to a given FILE. Default: STDOUT') do |file|
          options[:log_file] = file
        end
        opts.on('-v', '--verbose', 'Enable verbose logging') do
          options[:log_level] = :debug
        end
        opts.on('-L', '--log-level LEVEL', 'Set the log level explicitly') do |level|
          level_sym = level.to_s.downcase.to_sym
          unless Sensu::LOG_LEVELS.include?(level_sym)
            puts "Unknown log level #{level}"
            exit(1)
          end
          options[:log_level] = level_sym
        end
        opts.on('-b', '--background', 'Fork into the background') do
          options[:daemonize] = true
        end
        opts.on('-p', '--pid_file FILE', 'Write the PID to a given FILE') do |file|
          options[:pid_file] = file
        end
      end
      optparse.parse!(arguments)
      options
    end
  end
end
