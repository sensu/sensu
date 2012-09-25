class TestSensuMutateEventData < TestCase
  def test_built_in_mutator_only_output
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output]
    event = event_template(:output => "foo\nbar")
    assert_equal("foo\nbar", server.mutate_event_data(handler, event))
    done
  end

  def test_built_in_amqp_mutator_only_output_split
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output_split]
    event = event_template(:output => "foo\nbar")
    assert_equal(['foo', 'bar'], server.mutate_event_data(handler, event))
    done
  end
end
