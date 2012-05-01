class Array
  def deep_merge(other_array, &merger)
    concat(other_array).uniq
  end
end

class Hash
  alias_method :original_reader, :[]

  def [](key)
    if self.has_key?(key)
      original_reader(key)
    elsif key.is_a?(String)
      original_reader(key.to_sym)
    else
      original_reader(key)
    end
  end

  def method_missing(method, *arguments, &block)
    if self.has_key?(method)
      self[method]
    else
      super
    end
  end

  def deep_merge(other_hash, &merger)
    merger ||= Proc.new do |key, old_value, new_value|
      begin
        old_value.deep_merge(new_value, &merger)
      rescue
        new_value
      end
    end
    merge(other_hash, &merger)
  end
end

module Process
  def self.write_pid(pid_file)
    if pid_file.nil?
      raise('a pid file path must be provided')
    end
    begin
      File.open(pid_file, 'w') do |file|
        file.puts(self.pid)
      end
    rescue
      raise("could not write to pid file: #{pid_file}")
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
