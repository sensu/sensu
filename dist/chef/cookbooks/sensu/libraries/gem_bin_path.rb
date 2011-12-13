module GemBinPath
  def self.path(service)
    gems_path = "/usr/bin"
    ENV['PATH'].split(':').each do |path|
      if File.exists?(File.join(path, "sensu-#{service}"))
        gems_path = path
      end
    end
    gems_path
  end
end
