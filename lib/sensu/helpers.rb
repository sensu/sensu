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
end

class String
  def self.unique(chars=32)
    rand(36**chars).to_s(36)
  end
end
