module Sensu
  class Logger
    attr_reader :channel

    def initialize(options={})
      @channel = Cabin::Channel.get($0)
      @channel.subscribe(STDOUT)
      @channel.level = options[:verbose] ? :debug : options[:log_level] || :info
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
          @channel.error('log file is not writable', {
            :log_file => options[:log_file]
          })
        end
      end
    end

    def setup_traps(options={})
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @channel.level = @channel.level == :info ? :debug : :info
        end
      end
      if Signal.list.include?('USR2')
        Signal.trap('USR2') do
          reopen(options)
        end
      end
    end

    def self.get(options={})
      logger = self.new(options)
      logger.channel
    end
  end
end
