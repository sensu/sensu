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

  def deep_merge(hash)
    merger = proc do |key, value1, value2|
      value1.is_a?(Hash) && value2.is_a?(Hash) ? value1.merge(value2, &merger) : value2
    end
    self.merge(hash, &merger)
  end
end

class String
  def self.unique(chars=32)
    rand(36**chars).to_s(36)
  end
end
