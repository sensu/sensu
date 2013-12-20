require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Process' do
  include Helpers

  before do
    @process = Sensu::Process.new
  end

  it 'can create a pid file' do
    @process.write_pid('/tmp/sensu.pid')
    File.open('/tmp/sensu.pid', 'r').read.should eq(::Process.pid.to_s + "\n")
  end

  it 'can exit if it cannot create a pid file' do
    with_stdout_redirect do
      lambda { @process.write_pid('/sensu.pid') }.should raise_error(SystemExit)
    end
  end
end
