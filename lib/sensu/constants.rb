module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.9.11'

    SETTINGS_CATEGORIES = [:checks, :filters, :mutators, :handlers]

    EXTENSION_CATEGORIES = [:checks, :mutators, :handlers]

    SEVERITIES = %w[ok warning critical unknown]
  end
end
