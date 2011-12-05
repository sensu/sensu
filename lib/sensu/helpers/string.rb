class String
  def self.unique(chars=32)
    rand(36**chars).to_s(36)
  end
end
