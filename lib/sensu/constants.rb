module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.9.11'

    DEFAULT_OPTIONS = {
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d',
      :log_level => :info
    }

    SETTINGS_CATEGORIES = [:checks, :filters, :mutators, :handlers]

    EXTENSION_CATEGORIES = [:checks, :mutators, :handlers]

    SEVERITIES = %w[ok warning critical unknown]
  end
end
