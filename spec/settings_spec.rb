require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Settings' do
  include Helpers

  before do
    @settings = Sensu::Settings.new
  end

  it 'can load settings from configuration files' do
    @settings.load_file(options[:config_file])
    @settings.should respond_to(:to_hash, :[], :check_exists?, :mutator_exists?, :handler_exists?)
    @settings.check_exists?('tokens').should be_true
    @settings.check_exists?('nonexistent').should be_false
    @settings.check_exists?('unpublished').should be_true
    @settings.mutator_exists?('tag').should be_true
    @settings.mutator_exists?('nonexistent').should be_false
    @settings.handler_exists?('file').should be_true
    @settings.handler_exists?('nonexistent').should be_false
    @settings.check_exists?('merger').should be_true
    @settings[:checks][:merger][:command].should eq('this will be overwritten')
    options[:config_dirs].each do |config_dir|
      @settings.load_directory(config_dir)
    end
    @settings[:checks][:merger][:command].should eq('echo -n merger')
    @settings[:checks][:merger][:subscribers].should eq(['test'])
    @settings[:checks][:merger][:interval].should eq(60)
  end

  it 'can ignore invalid configuration snippets' do
    file_name = File.join(options[:config_dirs].first, 'invalid.json')
    File.open(file_name, 'w') do |file|
      file.write('invalid')
    end
    @settings.load_file(file_name)
    @settings.loaded_files.should be_empty
    File.delete(file_name)
  end

  it 'can read configuration from env' do
    ENV['RABBITMQ_URL'] = 'amqp://guest:guest@localhost:5672/'
    ENV['REDIS_URL'] = 'redis://username:password@localhost:6789'
    @settings[:rabbitmq].should be_nil
    @settings[:redis].should be_nil
    @settings.load_env
    @settings[:rabbitmq].should eq(ENV['RABBITMQ_URL'])
    @settings[:redis].should eq(ENV['REDIS_URL'])
  end

  it 'can validate the configuration' do
    @settings.load_file(options[:config_file])
    with_stdout_redirect do
      lambda { @settings.validate }.should raise_error(SystemExit)
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
    ENV['SENSU_CONFIG_FILES'].should include(File.expand_path(options[:config_file]))
  end

  it 'can provide indifferent access' do
    @settings.load_file(options[:config_file])
    @settings[:checks][:tokens].should be_kind_of(Hash)
    @settings['checks']['tokens'].should be_kind_of(Hash)
  end
end
