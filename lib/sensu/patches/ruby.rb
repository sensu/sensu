class Mash < Hashie::Mash
  def to_hash(options={})
    options[:symbolize_keys] ||= true
    super
  end
end

class Hash
  def symbolize_keys
    inject(Hash.new) do |result, (key, value)|
      new_key = key.is_a?(String) ? key.to_sym : key
      new_value = value.is_a?(Hash) ? value.symbolize_keys : value
      result[new_key] = new_value
      result
    end
  end

  def deep_diff(other_hash)
    (self.keys | other_hash.keys).inject(Hash.new) do |result, key|
      unless self[key] == other_hash[key]
        if self[key].is_a?(Hash) && other_hash[key].is_a?(Hash)
          result[key] = self[key].deep_diff(other_hash[key])
        else
          result[key] = [self[key], other_hash[key]]
        end
      end
      result
    end
  end

  def deep_merge(other_hash, &merger)
    merger ||= proc do |key, value, new_value|
      begin
        value.deep_merge(new_value, &merger)
      rescue
        new_value
      end
    end
    merge(other_hash, &merger)
  end
end

class Array
  def deep_merge(other_array, &merger)
    concat(other_array).uniq
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
      raise('could not write to pid file: ' + pid_file)
    end
  end

  def self.daemonize
    srand
    fork and exit
    unless session_id = self.setsid
      raise('cannot detach from controlling terminal')
    end
    trap 'SIGHUP', 'IGNORE'
    if pid = fork
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
    session_id
  end
end
