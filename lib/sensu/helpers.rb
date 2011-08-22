def symbolize_keys(item)
  case item
  when Array
    item.map do |i|
      symbolize_keys(i)
    end
  when Hash
    Hash[
          item.map do |key, value|
            k = key.is_a?(String) ? key.to_sym : key
            v = symbolize_keys(value)
            [k,v]
          end
        ]
  else
    item
  end
end
