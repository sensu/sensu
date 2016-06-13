module Sensu
  unless defined?(Sensu::VERSION)
    # Sensu release version.
    VERSION = "0.25.0.rc1".freeze

    # Sensu check severities.
    SEVERITIES = %w[ok warning critical unknown].freeze

    # Process signals that trigger a Sensu process stop.
    STOP_SIGNALS = %w[INT TERM].freeze
  end
end
