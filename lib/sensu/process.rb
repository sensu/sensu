module Sensu
  class Process
    def initialize(options={})
      if options[:daemonize]
        daemonize
      end
      if options[:pid_file]
        write_pid(options[:pid_file])
      end
      setup_eventmachine
    end

    def write_pid(pid_file)
      begin
        File.open(pid_file, 'w') do |file|
          file.puts(::Process.pid)
        end
      rescue
        raise('could not write to pid file: ' + pid_file)
      end
    end

    def daemonize
      srand
      if fork
        exit
      end
      unless ::Process.setsid
        raise('cannot detach from controlling terminal')
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
