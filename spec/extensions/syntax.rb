module Sensu
  module Extension
    class Syntax < Mutator
      def name
        'syntax'
      end

      def description
        'will raise a script error'
      end

      def run(event, &block)
          block.call('boom', 0)
        end
      end
    end
  end
end
