class TestSensuFilterEventData < TestCase
  def test_event_filtered
    server = Sensu::Server.new(@options)
    event = event_template
    assert(!server.event_filtered?('action', event))
    event[:action] = 'resolve'
    assert(server.event_filtered?('action', event))
    done
  end
end
