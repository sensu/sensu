require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Base' do
  include Helpers

  before do
    @base = Sensu::Base.new(options)
  end

  it 'can setup the logger' do
    logger = @base.logger
    expect(logger).to respond_to(:info, :warn, :error, :fatal)
  end

  it 'can load settings from configuration files' do
    ENV['SENSU_CONFIG_FILES'] = nil
    settings = @base.settings
    expect(settings).to respond_to(:validate, :[])
    expect(settings[:checks][:merger][:command]).to eq('echo -n merger')
    expect(settings[:checks][:merger][:subscribers]).to eq(['test'])
    expect(settings[:checks][:merger][:interval]).to eq(60)
    expect(ENV['SENSU_CONFIG_FILES']).to include(File.expand_path(options[:config_file]))
  end

  it 'can load extensions' do
    extensions = @base.extensions
    expect(extensions).to respond_to(:[])
    expect(extensions[:mutators]).to be_kind_of(Hash)
    expect(extensions[:handlers]).to be_kind_of(Hash)
    expect(extensions[:mutators]['only_check_output']).to be_an_instance_of(Sensu::Extension::OnlyCheckOutput)
    expect(extensions[:mutators]['opentsdb']).to be_an_instance_of(Sensu::Extension::OpenTSDB)
    expect(extensions[:handlers]['debug']).to be_an_instance_of(Sensu::Extension::Debug)
  end

  it 'can setup the current process' do
    @base.setup_process
    expect(EM::threadpool_size).to eq(20)
  end
end
