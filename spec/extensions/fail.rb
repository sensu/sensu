module Sensu
  module Extension
    class Fail < Mutator
      def name
        'fail'
      end

      def description
        'fails to do anything'
      end

      def run(event, settings, &block)
        block.call('fail', 2)
      end
    end
  end
end
