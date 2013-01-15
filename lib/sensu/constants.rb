module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.9.9'

    DEFAULT_OPTIONS = {
      :config_file => '/etc/sensu/config.json',
      :config_dir => '/etc/sensu/conf.d',
      :log_level => :info
    }

    SETTINGS_CATEGORIES = [:checks, :filters, :mutators, :handlers]

    EXTENSION_CATEGORIES = [:mutators, :handlers]

    SEVERITIES = %w[ok warning critical unknown]
  end
end
