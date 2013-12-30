module Sensu
  module Sandbox
    def self.eval(expression, value=nil)
      result = Proc.new do
        $SAFE = (RUBY_VERSION < '2.1.0' ? 4 : 3)
        Kernel.eval(expression)
      end
      result.call
    end
  end
end
