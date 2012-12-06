class TestSensuFilterEventData < TestCase
  def test_event_filtered
    server = Sensu::Server.new(@options)
    event = event_template
    assert(!server.event_filtered?('action', event))
    assert(server.event_filtered?('action_negated', event))
    event[:action] = 'resolve'
    assert(server.event_filtered?('action', event))
    assert(!server.event_filtered?('action_negated', event))
    assert(!server.event_filtered?('status', event))
    event[:check][:status] = 2
    assert(server.event_filtered?('status', event))
    done
  end

  def test_event_handlers_filtered
    server = Sensu::Server.new(@options)
    handlers = @settings[:handlers]
    event = event_template(:status => 2, :handlers => ["filter_action", "filter_status"])
    assert_equal([handlers[:filter_action]], server.event_handlers(event))
    event[:check][:handlers] = ["filter_action_status"]
    assert(server.event_handlers(event).empty?)
    event[:check][:handlers] = ["filter_nonexistent"]
    assert_equal([handlers[:filter_nonexistent]], server.event_handlers(event))
    done
  end
end
