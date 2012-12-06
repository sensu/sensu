module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.9.9.beta.1'
  end

  unless defined?(Sensu::DEFAULT_OPTIONS)
    DEFAULT_OPTIONS = {
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d'
    }
  end

  unless defined?(Sensu::SEVERITIES)
    SEVERITIES = %w[ok warning critical unknown]
  end
end
