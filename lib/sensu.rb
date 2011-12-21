# require 'daemons/daemonize'

module Sensu
  VERSION = "0.8.19"
  
  def self.write_pid(pid_file)
    File.open(pid_file, 'w') { |f| f.write(Process.pid.to_s + "\n") }
  end
    
  def self.daemonize
    srand # Split rand streams between spawning and daemonized process
    fork and exit # Fork and exit from the parent

    # Detach from the controlling terminal
    unless sess_id = Process.setsid
      raise 'cannot detach from controlling terminal'
    end

    trap 'SIGHUP', 'IGNORE'
    exit if pid = fork
  
    Dir.chdir "/"   # Release old working directory

    # Make sure all file descriptors are closed
    ObjectSpace.each_object(IO) do |io|
      unless [STDIN, STDOUT, STDERR].include?(io)
        begin
          unless io.closed?
            io.close
          end
        rescue ::Exception
        end
      end
    end

    return sess_id
  end
end
