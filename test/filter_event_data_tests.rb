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
end
