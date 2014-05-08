module Sensu
  class LogStream
    def initialize
      @log_stream = Array.new
      @log_stream_callbacks = Array.new
      @log_level = :info
      STDOUT.sync = true
      STDERR.reopen(STDOUT)
      setup_writer
    end

    def level=(level)
      @log_level = level
    end

    def level_filtered?(level)
      LOG_LEVELS.index(level) < LOG_LEVELS.index(@log_level)
    end

    def add(level, *arguments)
      unless level_filtered?(level)
        log_event = create_log_event(level, *arguments)
        if EM::reactor_running?
          schedule_write(log_event)
        else
          puts log_event
        end
      end
    end

    LOG_LEVELS.each do |level|
      define_method(level) do |*arguments|
        add(level, *arguments)
      end
    end

    def flush()
      @log_stream.each do |log_event|
        puts(log_event)
      end
    end

    def reopen(file)
      @log_file = file
      if File.writable?(file) || !File.exist?(file) && File.writable?(File.dirname(file))
        STDOUT.reopen(file, 'a')
        STDOUT.sync = true
        STDERR.reopen(STDOUT)
      else
        error('log file is not writable', {
          :log_file => file
        })
      end
    end

    def setup_traps
      if Signal.list.include?('USR1')
        Signal.trap('USR1') do
          @log_level = @log_level == :info ? :debug : :info
        end
      end
      if Signal.list.include?('USR2')
        Signal.trap('USR2') do
          if @log_file
            reopen(@log_file)
          end
        end
      end
    end

    private

    def create_log_event(level, message, data=nil)
      log_event = Hash.new
      log_event[:timestamp] = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%6N%z")
      log_event[:level] = level
      log_event[:message] = message
      if data.is_a?(Hash)
        log_event.merge!(data)
      end
      Oj.dump(log_event)
    end

    def schedule_write(log_event)
      EM::schedule do
        @log_stream << log_event
        unless @log_stream_callbacks.empty?
          @log_stream_callbacks.shift.call(@log_stream.shift)
        end
      end
    end

    def register_callback(&block)
      EM::schedule do
        if @log_stream.empty?
          @log_stream_callbacks << block
        else
          block.call(@log_stream.shift)
        end
      end
    end

    def setup_writer
      writer = Proc.new do |log_event|
        puts log_event
        EM::next_tick do
          register_callback(&writer)
        end
      end
      register_callback(&writer)
      EM::add_shutdown_hook do
        @log_stream.size.times do
          puts @log_stream.shift
        end
      end
    end
  end

  class Logger
    def self.get
      @logger ||= LogStream.new
    end
  end
end
