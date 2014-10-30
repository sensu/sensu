module Sensu
  unless defined?(Sensu::VERSION)
    VERSION = '0.15.0.beta.1'

    SEVERITIES = %w[ok warning critical unknown]

    STOP_SIGNALS = %w[INT TERM]
  end
end
