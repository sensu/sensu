module GemBinPath
  def self.path(service)
    gems_path = "/usr/bin"
    unless File.readable?("#{gems_path}/sensu-#{service}")
      Gem.path.each do |path|
        if File.readable?("#{path}/bin/sensu-#{service}")
          gems_path = path + "/bin"
        end
      end
    end
    gems_path
  end
end
