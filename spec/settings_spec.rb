require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Settings' do
  include Helpers

  before do
    @settings = Sensu::Settings.new
  end

  it 'can load settings from configuration files' do
    @settings.load_file(options[:config_file])
    expect(@settings).to respond_to(:to_hash, :[], :check_exists?, :mutator_exists?, :handler_exists?)
    expect(@settings.check_exists?('tokens')).to be_true
    expect(@settings.check_exists?('nonexistent')).to be_false
    expect(@settings.check_exists?('unpublished')).to be_true
    expect(@settings.mutator_exists?('tag')).to be_true
    expect(@settings.mutator_exists?('nonexistent')).to be_false
    expect(@settings.handler_exists?('file')).to be_true
    expect(@settings.handler_exists?('nonexistent')).to be_false
    expect(@settings.check_exists?('merger')).to be_true
    expect(@settings[:checks][:merger][:command]).to eq('this will be overwritten')
    options[:config_dirs].each do |config_dir|
      @settings.load_directory(config_dir)
    end
    expect(@settings[:checks][:merger][:command]).to eq('echo -n merger')
    expect(@settings[:checks][:merger][:subscribers]).to eq(['test'])
    expect(@settings[:checks][:merger][:interval]).to eq(60)
  end

  it 'can ignore invalid configuration snippets' do
    file_name = File.join(options[:config_dirs].first, 'invalid.json')
    File.open(file_name, 'w') do |file|
      file.write('invalid')
    end
    @settings.load_file(file_name)
    expect(@settings.loaded_files).to be_empty
    File.delete(file_name)
  end

  it 'can read configuration from env' do
    ENV['RABBITMQ_URL'] = 'amqp://guest:guest@localhost:5672/'
    ENV['REDIS_URL'] = 'redis://username:password@localhost:6789'
    expect(@settings[:rabbitmq]).to be_nil
    expect(@settings[:redis]).to be_nil
    @settings.load_env
    expect(@settings[:rabbitmq]).to eq(ENV['RABBITMQ_URL'])
    expect(@settings[:redis]).to eq(ENV['REDIS_URL'])
  end

  it 'can validate the configuration' do
    @settings.load_file(options[:config_file])
    with_stdout_redirect do
      expect { @settings.validate }.to raise_error(SystemExit)
    end
    options[:config_dirs].each do |config_dir|
      @settings.load_directory(config_dir)
    end
    @settings.validate
  end

  it 'can set environment variables' do
    ENV['SENSU_CONFIG_FILES'] = nil
    @settings.load_file(options[:config_file])
    @settings.set_env
    expect(ENV['SENSU_CONFIG_FILES']).to include(File.expand_path(options[:config_file]))
  end

  it 'can provide indifferent access' do
    @settings.load_file(options[:config_file])
    expect(@settings[:checks][:tokens]).to be_kind_of(Hash)
    expect(@settings['checks']['tokens']).to be_kind_of(Hash)
  end
end
