module Sensu
  module Extension
    class Fail < Mutator
      def name
        'fail'
      end

      def description
        'fails to do anything'
      end

      def run(event)
        yield('fail', 2)
      end
    end
  end
end
