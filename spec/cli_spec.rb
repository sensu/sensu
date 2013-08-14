require File.dirname(__FILE__) + '/../lib/sensu/cli.rb'
require File.dirname(__FILE__) + '/../lib/sensu/constants.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::CLI' do
  include Helpers

  it 'does not provide default configuration options' do
    Sensu::CLI.read.should eq(Hash.new)
  end

  it 'can parse command line arguments' do
    options = Sensu::CLI.read([
      '-c', 'spec/config.json',
      '-d', 'spec/conf.d',
      '-e', 'spec/extensions',
      '-v',
      '-l', '/tmp/sensu_spec.log',
      '-p', '/tmp/sensu_spec.pid',
      '-b'
    ])
    expected = {
      :config_file => 'spec/config.json',
      :config_dirs => ['spec/conf.d'],
      :extension_dir => 'spec/extensions',
      :log_level => :debug,
      :log_file => '/tmp/sensu_spec.log',
      :pid_file => '/tmp/sensu_spec.pid',
      :daemonize => true
    }
    options.should eq(expected)
  end

  it 'can set the appropriate log level' do
    options = Sensu::CLI.read([
      '-v',
      '-L', 'warn'
    ])
    expected = {
      :log_level => :warn
    }
    options.should eq(expected)
  end

  it 'exits when an invalid log level is provided' do
    with_stdout_redirect do
      lambda { Sensu::CLI.read(['-L', 'invalid']) }.should raise_error SystemExit
    end
  end
end
