def symbolize_keys(item)
  case item
  when Array
    item.map {|i| symbolize_keys(i)}
  when Hash
    Hash[
          item.map { |key, value|  
           k = key.is_a?(String) ? key.to_sym : key
           v = symbolize_keys(value)
           [k,v]
          }
        ]
  else
    item
  end
end
