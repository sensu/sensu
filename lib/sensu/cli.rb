require "optparse"
require "sensu/logger/constants"

module Sensu
  class CLI
    # Parse CLI arguments using Ruby stdlib `optparse`. This method
    # provides Sensu with process options (eg. log file), and can
    # provide users with information, such as the Sensu version.
    #
    # @param arguments [Array] to parse.
    # @return [Hash] options
    def self.read(arguments=ARGV)
      options = {}
      if File.exist?("/etc/sensu/config.json")
        options[:config_file] = "/etc/sensu/config.json"
      end
      if Dir.exist?("/etc/sensu/conf.d")
        options[:config_dirs] = ["/etc/sensu/conf.d"]
      end
      optparse = OptionParser.new do |opts|
        opts.on("-h", "--help", "Display this message") do
          puts opts
          exit
        end
        opts.on("-V", "--version", "Display version") do
          puts VERSION
          exit
        end
        opts.on("-c", "--config FILE", "Sensu JSON config FILE. Default: /etc/sensu/config.json (if exists)") do |file|
          options[:config_file] = file
        end
        opts.on("-d", "--config_dir DIR[,DIR]", "DIR or comma-delimited DIR list for Sensu JSON config files. Default: /etc/sensu/conf.d (if exists)") do |dir|
          options[:config_dirs] = dir.split(",")
        end
        opts.on("--validate_config", "Validate the compiled configuration and exit") do
          options[:validate_config] = true
        end
        opts.on("-P", "--print_config", "Print the compiled configuration and exit") do
          options[:print_config] = true
        end
        opts.on("-e", "--extension_dir DIR", "DIR for Sensu extensions") do |dir|
          options[:extension_dir] = dir
        end
        opts.on("-l", "--log FILE", "Log to a given FILE. Default: STDOUT") do |file|
          options[:log_file] = file
        end
        opts.on("-L", "--log_level LEVEL", "Log severity LEVEL") do |level|
          log_level = level.to_s.downcase.to_sym
          unless Logger::LEVELS.include?(log_level)
            puts "Unknown log level: #{level}"
            exit 1
          end
          options[:log_level] = log_level
        end
        opts.on("-v", "--verbose", "Enable verbose logging") do
          options[:log_level] = :debug
        end
        opts.on("-b", "--background", "Fork into the background") do
          options[:daemonize] = true
        end
        opts.on("-p", "--pid_file FILE", "Write the PID to a given FILE") do |file|
          options[:pid_file] = file
        end
      end
      optparse.parse!(arguments)
      options
    end
  end
end
