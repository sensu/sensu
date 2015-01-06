require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/server/process"

describe "Sensu::Server::Filter" do
  include Helpers

  before do
    @server = Sensu::Server::Process.new(options)
    settings = Sensu::Settings.get(options)
    @filters = settings[:filters]
    @handler = {}
    @event = event_template
  end

  it "can determine if an action is subdued" do
    expect(@server.action_subdued?(Hash.new)).to be(false)
    condition = {
      :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
      :end => (Time.now + 3600).strftime("%l:00 %p").strip
    }
    expect(@server.action_subdued?(condition)).to be(true)
    condition = {
      :begin => (Time.now + 3600).strftime("%l:00 %p").strip,
      :end => (Time.now + 7200).strftime("%l:00 %p").strip
    }
    expect(@server.action_subdued?(condition)).to be(false)
    condition = {
      :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
      :end => (Time.now - 7200).strftime("%l:00 %p").strip
    }
    expect(@server.action_subdued?(condition)).to be(true)
    condition = {
      :begin => (Time.now + 3600).strftime("%l:00 %p").strip,
      :end => (Time.now - 7200).strftime("%l:00 %p").strip
    }
    expect(@server.action_subdued?(condition)).to be(false)
    condition = {
      :days => [
        Time.now.strftime("%A"),
        "wednesday"
      ]
    }
    expect(@server.action_subdued?(condition)).to be(true)
    condition = {
      :days => [
        (Time.now + 86400).strftime("%A"),
        (Time.now + 172800).strftime("%A")
      ]
    }
    expect(@server.action_subdued?(condition)).to be(false)
    condition = {
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :begin => (Time.now + 3600).rfc2822,
          :end => (Time.now + 7200)
        }
      ]
    }
    expect(@server.action_subdued?(condition)).to be(true)
    condition = {
      :days => %w[sunday monday tuesday wednesday thursday friday saturday],
      :exceptions => [
        {
          :begin => (Time.now - 3600).rfc2822,
          :end => (Time.now + 3600).rfc2822
        }
      ]
    }
    expect(@server.action_subdued?(condition)).to be(false)
  end

  it "can determine if a handler is subdued" do
    expect(@server.handler_subdued?(@handler, @event)).to be(false)
    @event[:check] = {
      :subdue => {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
    }
    expect(@server.handler_subdued?(@handler, @event)).to be(true)
    @event[:check][:subdue][:at] = "publisher"
    expect(@server.handler_subdued?(@handler, @event)).to be(false)
    @handler[:subdue] = {
      :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
      :end => (Time.now + 3600).strftime("%l:00 %p").strip
    }
    expect(@server.handler_subdued?(@handler, @event)).to be(true)
  end

  it "can determine if a check request is subdued" do
    check = {
      :subdue => {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
    }
    expect(@server.check_request_subdued?(check)).to be(false)
    check[:subdue][:at] = "publisher"
    expect(@server.check_request_subdued?(check)).to be(true)
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
  end

  it "can determine if filter attributes match an event" do
    attributes = {
      :occurrences => 1
    }
    expect(@server.filter_attributes_match?(attributes, @event)).to be(true)
    @event[:occurrences] = 2
    expect(@server.filter_attributes_match?(attributes, @event)).to be(false)
    attributes[:occurrences] = "eval: value == 1 || value % 60 == 0"
    @event[:occurrences] = 1
    expect(@server.filter_attributes_match?(attributes, @event)).to be(true)
    @event[:occurrences] = 2
    expect(@server.filter_attributes_match?(attributes, @event)).to be(false)
    @event[:occurrences] = 120
    expect(@server.filter_attributes_match?(attributes, @event)).to be(true)
  end

  it "can filter an event using a filter" do
    async_wrapper do
      @event[:client][:environment] = "production"
      @server.event_filter("production", @event) do |filtered|
        expect(filtered).to be(false)
        @server.event_filter("development", @event) do |filtered|
          expect(filtered).to be(true)
          @server.event_filter("nonexistent", @event) do |filtered|
            expect(filtered).to be(false)
            handler = {
              :filter => "development"
            }
            @server.event_filtered?(handler, @event) do |filtered|
              expect(filtered).to be(true)
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
      handler[:subdue] = {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
      @server.filter_event(handler, @event) do
        raise "not filtered"
      end
      handler.delete(:subdue)
      @server.filter_event(handler, @event) do |event|
        expect(event).to be(@event)
        async_done
      end
    end
  end
end
