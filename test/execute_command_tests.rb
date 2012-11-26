class TestSensuExecuteCommand < TestCase
  def test_execute_command
    server = Sensu::Server.new(@options)
    server.execute_command('echo "test"') do |output, status|
      assert_equal("test\n", output)
      assert_equal(0, status)
      done
    end
  end

  def test_execute_nonexistent_command
    server = Sensu::Server.new(@options)
    server.execute_command('nonexistent.command') do |output, status|
      assert(output =~ /nonexistent.command/)
      assert_equal(127, status)
      done
    end
  end
end
