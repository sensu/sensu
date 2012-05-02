class Hash
  def method_missing(method, *arguments, &block)
    if has_key?(method)
      self[method]
    else
      super
    end
  end
end
