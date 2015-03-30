module Sensu
  unless defined?(Sensu::VERSION)
    # Sensu release version.
    VERSION = "0.17.1"

    # Sensu check severities.
    SEVERITIES = %w[ok warning critical unknown]

    # Process signals that trigger a Sensu process stop.
    STOP_SIGNALS = %w[INT TERM]
  end
end
