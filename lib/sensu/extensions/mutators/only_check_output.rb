module Sensu
  module Extension
    class OnlyCheckOutput < Mutator
      def name
        'only_check_output'
      end

      def description
        'only returns check output'
      end

      def run(event, &block)
        block.call(event[:check][:output], 0)
      end
    end
  end
end
