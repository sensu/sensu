module Sensu
  unless defined?(Sensu::VERSION)
    # Sensu release version.
    VERSION = "1.9.0".freeze

    # Sensu release information.
    RELEASE_INFO = {
      :version => VERSION
    }

    # Sensu check severities.
    SEVERITIES = %w[ok warning critical unknown].freeze

    # Process signals that trigger a Sensu process stop.
    STOP_SIGNALS = %w[INT TERM].freeze
  end
end
