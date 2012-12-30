class TestSensuIO < TestCase
  def test_popen_successful_command
    output, status = Sensu::IO.popen('echo -n "test"')
    assert_equal('test', output)
    assert_equal(0, status)
    done
  end

  def test_popen_timed_out_command
    output, status = Sensu::IO.popen('sleep 2 && echo "Ruby 1.8"', 'r', 0.25)
    if RUBY_VERSION < '1.9.0'
      assert_equal('Ruby 1.8', output)
      assert_equal(0, status)
    else
      assert_equal('Execution timed out', output)
      assert_equal(2, status)
    end
    done
  end

  def test_popen_nonexistent_command
    output, status = Sensu::IO.popen('nonexistent.command')
    assert(output =~ /nonexistent.command/)
    assert_equal(127, status)
    done
  end
end
