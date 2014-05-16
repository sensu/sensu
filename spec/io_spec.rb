require File.dirname(__FILE__) + '/../lib/sensu/io.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::IO' do
  include Helpers

  it 'can execute a command' do
    output, status = Sensu::IO.popen('echo test')
    expect(output).to eq("test\n")
    expect(status).to eq(0)
  end

  it 'can execute a command with a non-zero exist status' do
    output, status = Sensu::IO.popen('echo test && exit 1')
    expect(output).to eq("test\n")
    expect(status).to eq(1)
  end

  it 'can execute an unknown command' do
    output, status = Sensu::IO.popen('unknown.command')
    expect(output).to include('unknown')
    expect(status).to eq(127)
  end

  it 'can time out command execution (ruby 1.9.3 only)' do
    output, status = Sensu::IO.popen('sleep 1 && echo -n "Ruby 1.8"', 'r', 0.25)
    if RUBY_VERSION < '1.9.3'
      expect(output).to eq('Ruby 1.8')
      expect(status).to eq(0)
    else
      expect(output).to eq('Execution timed out')
      expect(status).to eq(2)
    end
  end

  it 'can execute a command and write to stdin' do
    content = 'foo_bar_baz'
    file_name = File.join('/tmp', content)
    output, status = Sensu::IO.popen('cat > ' + file_name, 'r+') do |child|
      child.write(content)
      child.close_write
    end
    expect(output).to be_empty
    expect(status).to eq(0)
    expect(File.exists?(file_name)).to be_true
    expect(File.open(file_name, 'r').read).to eq(content)
    File.delete(file_name)
  end

  it 'can execute a command asynchronously' do
    async_wrapper do
      Sensu::IO.async_popen('echo fail && exit 2') do |output, status|
        expect(output).to eq("fail\n")
        expect(status).to eq(2)
        async_done
      end
    end
  end

  it 'can execute a command asynchronously and write to stdin' do
    timestamp = epoch.to_s
    file_name = File.join('/tmp', timestamp)
    async_wrapper do
      Sensu::IO.async_popen('cat > ' + file_name, timestamp) do |output, status|
        expect(status).to eq(0)
        async_done
      end
    end
    expect(File.exists?(file_name)).to be_true
    expect(File.open(file_name, 'r').read).to eq(timestamp)
    File.delete(file_name)
  end
end
