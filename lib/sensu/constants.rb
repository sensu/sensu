module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.9.6.beta.5'
  end

  unless defined?(Sensu::DEFAULT_OPTIONS)
    DEFAULT_OPTIONS = {
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d'
    }
  end
end
