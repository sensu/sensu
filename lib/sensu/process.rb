module Sensu
  class Process
    def initialize
      @logger = Cabin::Channel.get
    end

    def write_pid(file)
      begin
        File.open(file, 'w') do |pid_file|
          pid_file.puts(::Process.pid)
        end
      rescue
        @logger.fatal('could not write to pid file', {
          :pid_file => file
        })
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
    end

    def daemonize
      srand
      if fork
        exit
      end
      unless ::Process.setsid
        @logger.fatal('cannot detach from controlling terminal')
        @logger.fatal('SENSU NOT RUNNING!')
        exit 2
      end
      Signal.trap('SIGHUP', 'IGNORE')
      if fork
        exit
      end
      Dir.chdir('/')
      ObjectSpace.each_object(IO) do |io|
        unless [STDIN, STDOUT, STDERR].include?(io)
          begin
            unless io.closed?
              io.close
            end
          rescue
          end
        end
      end
    end

    def setup_eventmachine
      EM::threadpool_size = 14
    end
  end
end
