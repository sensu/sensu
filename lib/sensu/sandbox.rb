module Sensu
  module Sandbox
    # Evaluate a Ruby expression within the context of a simple
    # "sandbox", a Proc in a module method. As of Ruby 2.3.0,
    # `$SAFE` no longer supports levels > 1, so its use has been
    # removed from this method. A single value is provided to the
    # "sandbox".
    #
    # @param expression [String] to be evaluated.
    # @param value [Object] to provide the "sandbox" with.
    # @return [Object]
    def self.eval(expression, value=nil)
      result = Proc.new do
        Kernel.eval(expression)
      end
      result.call
    end
  end
end
