module Sensu
  module Server
    module Sandbox
      # Evaluate a Ruby expression within the context of a simple
      # "sandbox", a Proc in a module method. Use the Ruby `$SAFE`
      # level of 4 when the version of Ruby is less than 2.1.0. A
      # single value is provided to the "sandbox".
      #
      # @param expression [String] to be evaluated.
      # @param value [Object] to provide the "sandbox" with.
      # @return [Object]
      def self.eval(expression, value=nil)
        result = Proc.new do
          $SAFE = (RUBY_VERSION < "2.1.0" ? 4 : 3)
          Kernel.eval(expression)
        end
        result.call
      end
    end
  end
end
