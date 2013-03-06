require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Extensions' do
  include Helpers

  before do
    @extensions = Sensu::Extensions.new
  end

  it 'can load the default extensions' do
    @extensions.should respond_to(:[], :mutator_exists?, :handler_exists?)
    @extensions[:mutators].should be_kind_of(Hash)
    @extensions[:mutators].should be_empty
    @extensions[:handlers].should be_kind_of(Hash)
    @extensions[:handlers].should be_empty
    @extensions.load_all
    @extensions[:mutators]['only_check_output'].should be_an_instance_of(Sensu::Extension::OnlyCheckOutput)
    @extensions[:handlers]['debug'].should be_an_instance_of(Sensu::Extension::Debug)
  end

  it 'can load custom extensions and ignore those with syntax errors' do
    @extensions.require_directory(options[:extension_dir])
    @extensions.load_all
    @extensions.mutator_exists?('opentsdb')
    @extensions[:mutators]['opentsdb'].should be_an_instance_of(Sensu::Extension::OpenTSDB)
  end

  it 'can stop all extensions for cleanup purposes' do
    @extensions.load_all
    stopped_all = false
    @extensions.stop_all do
      stopped_all = true
    end
    stopped_all.should be_true
  end
end
