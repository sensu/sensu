module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.17.0.beta'

    SEVERITIES = %w[ok warning critical unknown]

    STOP_SIGNALS = %w[INT TERM]
  end
end
