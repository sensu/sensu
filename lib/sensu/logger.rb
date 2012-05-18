module Sensu
  class Logger
    def initialize(options={})
      @logger = Cabin::Channel.get
      @logger.subscribe(STDOUT)
      @logger.level = options[:verbose] ? :debug : options[:log_level] || :info
      @log_file = options[:log_file]
    end

    def reopen(file=nil)
      file ||= @log_file
      unless file.nil?
        @log_file = file
        if File.writable?(file) || !File.exist?(file) && File.writable?(File.dirname(file))
          STDOUT.reopen(file, 'a')
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
        else
          @logger.error('log file is not writable', {
            :log_file => file
          })
        end
      end
    end

    def setup_traps
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @logger.level = @logger.level == :info ? :debug : :info
        end
      end
      if Signal.list.include?('USR2')
        Signal.trap('USR2') do
          reopen(@log_file)
        end
      end
    end
  end
end
