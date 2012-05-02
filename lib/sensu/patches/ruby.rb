class Hash
  def method_missing(method, *arguments, &block)
    if has_key?(method)
      self[method]
    else
      super
    end
  end
end

module Process
  def self.write_pid(pid_file)
    if pid_file.nil?
      raise('a pid file path must be provided')
    end
    begin
      File.open(pid_file, 'w') do |file|
        file.puts(pid)
      end
    rescue
      raise('could not write to pid file: ' + pid_file)
    end
  end

  def self.daemonize
    srand
    if fork
      exit
    end
    unless setsid
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
end
