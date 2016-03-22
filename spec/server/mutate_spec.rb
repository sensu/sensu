require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/process"

describe "Sensu::Server::Mutate" do
  include Helpers

  before do
    @server = Sensu::Server::Process.new(options)
    @event = event_template
  end

  it "can mutate event data" do
    async_wrapper do
      handler = {
        :mutator => "unknown"
      }
      @server.mutate_event(handler, @event) do |event_data|
        raise "should never get here"
      end
      handler[:mutator] = "explode"
      @server.mutate_event(handler, @event) do |event_data|
        raise "should never get here"
      end
      handler[:mutator] = "fail"
      @server.mutate_event(handler, @event) do |event_data|
        raise "should never get here"
      end
      handler.delete(:mutator)
      @server.mutate_event(handler, @event) do |event_data|
        expected = Sensu::JSON.dump(@event)
        expect(Sensu::JSON.load(event_data)).to eq(Sensu::JSON.load(expected))
        handler[:mutator] = "only_check_output"
        @server.mutate_event(handler, @event) do |event_data|
          expect(event_data).to eq("WARNING")
          handler[:mutator] = "tag"
          @server.mutate_event(handler, @event) do |event_data|
            expect(Sensu::JSON.load(event_data)).to include(:mutated)
            async_done
          end
        end
      end
    end
  end
end
