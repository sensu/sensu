class Object
  def to_obj
    self
  end
end

class Hash
  def to_mod
    hash = self
    Module.new do
      hash.each_pair do |key, value|
        define_method key do
          value.to_obj
        end
      end
    end
  end

  def to_obj
    Object.new.extend self.to_mod
  end

  def symbolize_keys(item = self)
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
