class TestSensuMutateEventData < TestCase
  def test_built_in_mutator_only_output
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output]
    event = event_template(:output => "foo\nbar")
    server.mutate_event_data(handler, event) do |event_data|
      assert_equal("foo\nbar", event_data)
      done
    end
  end

  def test_built_in_amqp_mutator_only_output_split
    server = Sensu::Server.new(@options)
    handler = @settings[:handlers][:only_output_split]
    event = event_template(:output => "foo\nbar")
    server.mutate_event_data(handler, event) do |event_data|
      assert_equal(['foo', 'bar'], event_data)
      done
    end
  end
end
