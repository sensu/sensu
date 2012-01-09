class Array
  def deep_merge(other_array, &merger)
    concat(other_array).uniq
  end
end

class Hash
  def symbolize_keys(item=self)
    case item
    when Array
      item.map do |i|
        symbolize_keys(i)
      end
    when Hash
      Hash[
        item.map do |key, value|
          new_key = key.is_a?(String) ? key.to_sym : key
          new_value = symbolize_keys(value)
          [new_key, new_value]
        end
      ]
    else
      item
    end
  end

  def deep_diff(hash)
    (self.keys | hash.keys).inject(Hash.new) do |diff, key|
      unless self[key] == hash[key]
        if self[key].is_a?(Hash) && hash[key].is_a?(Hash)
          diff[key] = self[key].deep_diff(hash[key])
        else
          diff[key] = [self[key], hash[key]]
        end
      end
      diff
    end
  end

  def deep_merge(other_hash, &merger)
    merger ||= proc do |key, oldval, newval|
      oldval.deep_merge(newval, &merger) rescue newval
    end
    merge(other_hash, &merger)
  end
end

class String
  def self.unique(chars=32)
    rand(36**chars).to_s(36)
  end
end

module Process
  def self.write_pid(pid_file)
    if pid_file.nil?
      raise 'a pid file path must be provided'
    end
    begin
      File.open(pid_file, 'w') do |file|
        file.write(self.pid.to_s + "\n")
      end
    rescue
      raise 'could not write to pid file: ' + pid_file
    end
  end

  def self.daemonize
    srand
    fork and exit
    unless session_id = self.setsid
      raise 'cannot detach from controlling terminal'
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
    return session_id
  end
end
