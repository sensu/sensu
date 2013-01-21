module Sensu
  module Extension
    class Debug < Handler
      def name
        'debug'
      end

      def description
        'outputs json event data'
      end

      def run(event, settings, &block)
        block.call(event.to_json, 0)
      end
    end
  end
end
