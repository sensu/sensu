class TestSensuIO < TestCase
  def test_popen_successful_command
    output, status = Sensu::IO.popen('echo -n "test"')
    assert_equal('test', output)    
    assert_equal(0, status)
    done
  end

  def test_popen_timed_out_command
    output, status = Sensu::IO.popen('sleep 10', 'r', 0.25)
    assert_equal('Execution timed out', output)    
    assert_equal(2, status)
    done
  end

  def test_popen_nonexistent_command
    output, status = Sensu::IO.popen('nonexistent.command')
    assert(output =~ /nonexistent.command/)
    assert_equal(127, status)
    done
  end
end
