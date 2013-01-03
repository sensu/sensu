class TestSensuMutateEventData < TestCase
  def test_mutator_extension_only_check_output
    server = Sensu::Server.new(@options)
    event = event_template(:output => "foo\nbar")
    server.mutate_event_data('only_check_output', event) do |event_data|
      assert_equal("foo\nbar", event_data)
      done
    end
  end
end
