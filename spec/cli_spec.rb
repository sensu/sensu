require File.dirname(__FILE__) + '/../lib/sensu/cli.rb'
require File.dirname(__FILE__) + '/../lib/sensu/constants.rb'

describe 'Sensu::CLI' do
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
      :config_dir => 'spec/conf.d',
      :extension_dir => 'spec/extensions',
      :log_level => :debug,
      :log_file => '/tmp/sensu_spec.log',
      :pid_file => '/tmp/sensu_spec.pid',
      :daemonize => true
    }
    options.should eq(expected)
  end
end
