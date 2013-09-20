require File.dirname(__FILE__) + '/../lib/sensu/io.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::IO' do
  include Helpers

  it 'can execute a command' do
    output, status = Sensu::IO.popen('echo test')
    output.should eq("test\n")
    status.should eq(0)
  end

  it 'can execute a command with a non-zero exist status' do
    output, status = Sensu::IO.popen('echo test && exit 1')
    output.should eq("test\n")
    status.should eq(1)
  end

  it 'can execute an unknown command' do
    output, status = Sensu::IO.popen('unknown.command')
    output.should include('unknown')
    status.should eq(127)
  end

  it 'can time out command execution (ruby 1.9.3 only)' do
    output, status = Sensu::IO.popen('sleep 1 && echo -n "Ruby 1.8"', 'r', 0.25)
    if RUBY_VERSION < '1.9.3'
      output.should eq('Ruby 1.8')
      status.should eq(0)
    else
      output.should eq('Execution timed out')
      status.should eq(2)
    end
  end

  it 'can execute a command and write to stdin' do
    content = 'foo_bar_baz'
    file_name = File.join('/tmp', content)
    output, status = Sensu::IO.popen('cat > ' + file_name, 'r+') do |child|
      child.write(content)
      child.close_write
    end
    output.should be_empty
    status.should eq(0)
    File.exists?(file_name).should be_true
    File.open(file_name, 'r').read.should eq(content)
    File.delete(file_name)
  end

  it 'can execute a command asynchronously' do
    async_wrapper do
      Sensu::IO.async_popen('echo fail && exit 2') do |output, status|
        output.should eq("fail\n")
        status.should eq(2)
        async_done
      end
    end
  end

  it 'can execute a command asynchronously and write to stdin' do
    timestamp = epoch.to_s
    file_name = File.join('/tmp', timestamp)
    async_wrapper do
      Sensu::IO.async_popen('cat > ' + file_name, timestamp) do |output, status|
        status.should eq(0)
        async_done
      end
    end
    File.exists?(file_name).should be_true
    File.open(file_name, 'r').read.should eq(timestamp)
    File.delete(file_name)
  end
end
