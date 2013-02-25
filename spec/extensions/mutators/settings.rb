module Sensu
  module Extension
    class Settings < Mutator
      def name
        'settings'
      end

      def description
        'tests the settings hash passed to extension run()'
      end

      def run(event, settings, &block)
        block.call(settings.has_key?(:handlers).to_s, 0)
      end
    end
  end
end
