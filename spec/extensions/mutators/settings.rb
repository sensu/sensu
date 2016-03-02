module Sensu
  module Extension
    class Settings < Mutator
      def name
        'settings'
      end

      def description
        'tests the loaded settings hash'
      end

      def run(event)
        yield(settings.has_key?(:handlers).to_s, 0)
      end
    end
  end
end
