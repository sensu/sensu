gem 'cabin', '0.4.4'

require 'cabin'

module Sensu
  class LogStream
    attr_reader :logger

    def initialize
      @logger = Cabin::Channel.get
      STDOUT.sync = true
      STDERR.reopen(STDOUT)
      @logger.subscribe(STDOUT)
    end

    def level=(log_level)
      @logger.level = log_level
    end

    def reopen(file)
      @log_file = file
      if File.writable?(file) || !File.exist?(file) && File.writable?(File.dirname(file))
        STDOUT.reopen(file, 'a')
        STDOUT.sync = true
        STDERR.reopen(STDOUT)
      else
        @logger.error('log file is not writable', {
          :log_file => file
        })
      end
    end

    def setup_traps
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @logger.level = @logger.level == :info ? :debug : :info
        end
      end
      if @log_file && Signal.list.include?('USR2')
        Signal.trap('USR2') do
          reopen(@log_file)
        end
      end
    end
  end

  class Logger
    def self.get
      Cabin::Channel.get
    end
  end

  class NullLogger
    [:debug, :info, :warn, :error, :fatal].each do |method|
      define_method(method) do |*arguments|
      end
    end

    def self.get
      self.new
    end
  end
end
