class TestSensuMutateEventData < TestCase
  def test_mutator_extension_only_check_output
    server = Sensu::Server.new(@options)
    event = event_template(:output => "foo\nbar")
    server.mutate_event_data('only_check_output', event) do |event_data|
      assert_equal("foo\nbar", event_data)
      done
    end
  end

  def test_mutator_extension_opentsdb
    server = Sensu::Server.new(@options)
    event = event_template(:output => "foo 42 1357240067\nbar 42 1357240067")
    server.mutate_event_data('opentsdb', event) do |event_data|
      assert(event_data =~ /foo 1357240067 42/)
      done
    end
  end
end
