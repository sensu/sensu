require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/daemon'

describe 'Sensu::Daemon' do
  include Helpers

  before do
    class Test
      include Sensu::Daemon
    end
    @daemon = Test.new(:log_level => :fatal)
  end

  it 'can create a pid file' do
    @daemon.setup_process(:pid_file => '/tmp/sensu.pid')
    expect(IO.read('/tmp/sensu.pid')).to eq(Process.pid.to_s + "\n")
  end

  it 'can exit if it cannot create a pid file' do
    with_stdout_redirect do
      expect { @daemon.setup_process(:pid_file => '/sensu.pid') }.to raise_error(SystemExit)
    end
  end
end
