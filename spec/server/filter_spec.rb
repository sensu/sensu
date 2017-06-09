require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/process"

describe "Sensu::Server::Filter" do
  include Helpers

  before do
    @server = Sensu::Server::Process.new(options)
    @handler = {}
    @event = event_template
  end

  it "can determine if handler handles a silenced event" do
    expect(@server.handler_silenced?(@handler, @event)).to be(false)
    @event[:silenced] = true
    expect(@server.handler_silenced?(@handler, @event)).to be(true)
    @handler[:handle_silenced] = true
    expect(@server.handler_silenced?(@handler, @event)).to be(false)
    @handler[:handle_silenced] = false
    expect(@server.handler_silenced?(@handler, @event)).to be(true)
  end

  it "can determine if handling is disabled for an event" do
    expect(@server.handling_disabled?(@event)).to be(false)
    @event[:check][:handle] = false
    expect(@server.handling_disabled?(@event)).to be(true)
  end

  it "can determine if a handler handles an action" do
    expect(@server.handle_action?(@handler, @event)).to be(true)
    @event[:action] = :flapping
    expect(@server.handle_action?(@handler, @event)).to be(false)
    @handler[:handle_flapping] = true
    expect(@server.handle_action?(@handler, @event)).to be(true)
  end

  it "can determine if a handler handles a severity" do
    handler = {
      :severities => ["critical"]
    }
    expect(@server.handle_severity?(handler, @event)).to be(false)
    @event[:check][:status] = 2
    expect(@server.handle_severity?(handler, @event)).to be(true)
    @event[:check][:status] = 0
    expect(@server.handle_severity?(handler, @event)).to be(false)
    @event[:action] = :resolve
    @event[:check][:history] = [1, 0]
    expect(@server.handle_severity?(handler, @event)).to be(false)
    @event[:check][:history] = [1, 2, 0]
    expect(@server.handle_severity?(handler, @event)).to be(true)
    @event[:check][:history] = [0, 0, 1, 2, 0]
    expect(@server.handle_severity?(handler, @event)).to be(true)
    @event[:check][:history] = [0, 0, 1, 2, 1, 0]
    expect(@server.handle_severity?(handler, @event)).to be(true)
    @event[:check][:history] = [0, 0, 1, 2, 1, 0, 0]
    expect(@server.handle_severity?(handler, @event)).to be(true)
  end

  it "can determine if filter attributes match an event" do
    attributes = {
      :occurrences => 1,
      :action => "resolve"
    }
    expect(@server.attributes_match?(@event, attributes)).to be(false)
    attributes[:action] = "create"
    expect(@server.attributes_match?(@event, attributes)).to be(true)
    @event[:occurrences] = 2
    expect(@server.attributes_match?(@event, attributes)).to be(false)
  end

  it "can determine if filter eval attributes match an event" do
    attributes = {
      :occurrences => "eval: value == 3 || value % 60 == 0"
    }
    expect(@server.attributes_match?(@event, attributes)).to be(false)
    @event[:occurrences] = 3
    expect(@server.attributes_match?(@event, attributes)).to be(true)
    @event[:occurrences] = 4
    expect(@server.attributes_match?(@event, attributes)).to be(false)
    @event[:occurrences] = 120
    expect(@server.attributes_match?(@event, attributes)).to be(true)
    @event[:occurrences] = 3
    attributes[:occurrences] = "eval: value == :::check.occurrences:::"
    expect(@server.attributes_match?(@event, attributes)).to be(false)
    attributes[:occurrences] = "eval: value == :::check.occurrences|3:::"
    expect(@server.attributes_match?(@event, attributes)).to be(true)
    @event[:check][:occurrences] = 2
    expect(@server.attributes_match?(@event, attributes)).to be(false)
    @event[:occurrences] = 2
    expect(@server.attributes_match?(@event, attributes)).to be(true)
  end

  it "can filter an event using a filter" do
    async_wrapper do
      @event[:client][:environment] = "production"
      @server.event_filter("production", @event) do |filtered, filter_name|
        expect(filtered).to be(false)
        expect(filter_name).to eq("production")
        @server.event_filter("development", @event) do |filtered, filter_name|
          expect(filtered).to be(true)
          expect(filter_name).to eq("development")
          @server.event_filter("nonexistent", @event) do |filtered|
            expect(filtered).to be(false)
            handler = {
              :filter => "development"
            }
            @server.event_filtered?(handler, @event) do |filtered, filter_name|
              expect(filtered).to be(true)
              expect(filter_name).to eq("development")
              handler = {
                :filters => ["production"]
              }
              @server.event_filtered?(handler, @event) do |filtered|
                expect(filtered).to be(false)
                handler[:filters] = ["production", "development"]
                @server.event_filtered?(handler, @event) do |filtered|
                  expect(filtered).to be(true)
                  async_done
                end
              end
            end
          end
        end
      end
    end
  end

  it "can filter events for a specific time window" do
    async_wrapper do
      @server.event_filter("time", @event) do |filtered|
        expect(filtered).to be(true)
        @server.settings[:filters][:time] = {
          :when => {
            :days => {
              :all => [
                {
                  :begin => (Time.now + 3600).strftime("%l:00 %p").strip,
                  :end => (Time.now + 5400).strftime("%l:00 %p").strip
                }
              ]
            }
          }
        }
        @server.event_filter("time", @event) do |filtered|
          expect(filtered).to be(false)
          async_done
        end
      end
    end
  end

  it "can filter events" do
    async_wrapper do
      handler = {
        :handle_flapping => false
      }
      @event[:action] = :flapping
      @server.filter_event(handler, @event) do
        raise "not filtered"
      end
      handler.delete(:handle_flapping)
      @event[:action] = :create
      @event[:check][:handle] = false
      @server.filter_event(handler, @event) do
        raise "not filtered"
      end
      @event[:check].delete(:handle)
      handler[:severities] = ["critical"]
      @server.filter_event(handler, @event) do
        raise "not filtered"
      end
      handler.delete(:severities)
      @event[:silenced] = true
      @server.filter_event(handler, @event) do
        raise "not filtered"
      end
      @event[:silenced] = false
      @server.filter_event(handler, @event) do |event|
        expect(event).to be(@event)
        async_done
      end
    end
  end

  it "can catch SyntaxErrors in eval filters" do
    attributes = {
      :occurrences => "eval: raise SyntaxError"
    }
    expect(@server.attributes_match?(@event, attributes)).to be(false)
  end
end
