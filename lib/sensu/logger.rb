module Sensu
  class Logger
    def initialize(options={})
      @logger = Cabin::Channel.get
      @logger.subscribe(STDOUT)
      @logger.level = options[:verbose] ? :debug : options[:log_level] || :info
      reopen(options)
      setup_traps(options)
    end

    def reopen(options={})
      unless options[:log_file].nil?
        if File.writable?(options[:log_file]) ||
            !File.exist?(options[:log_file]) && File.writable?(File.dirname(options[:log_file]))
          STDOUT.reopen(options[:log_file], 'a')
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
        else
          @logger.error('log file is not writable', {
            :log_file => options[:log_file]
          })
        end
      end
    end

    def setup_traps(options={})
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @logger.level = @logger.level == :info ? :debug : :info
        end
      end
      if Signal.list.include?('USR2')
        Signal.trap('USR2') do
          reopen(options)
        end
      end
    end
  end
end
