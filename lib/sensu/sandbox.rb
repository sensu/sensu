module Sensu
  module Sandbox
    def self.eval(expression, value=nil)
      result = Proc.new do
        $SAFE = 4
        Kernel.eval(expression)
      end
      result.call
    end
  end
end
