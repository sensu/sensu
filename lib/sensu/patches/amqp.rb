module AMQP
  module Client
    def reconnecting?
      @reconnecting || false
    end
  end
end
