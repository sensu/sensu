module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.11.0'

    LOG_LEVELS = [:debug, :info, :warn, :error, :fatal]

    SETTINGS_CATEGORIES = [:checks, :filters, :mutators, :handlers]

    EXTENSION_CATEGORIES = [:checks, :mutators, :handlers]

    SEVERITIES = %w[ok warning critical unknown]

    STOP_SIGNALS = %w[INT TERM]
  end
end
