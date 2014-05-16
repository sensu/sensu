require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Extensions' do
  include Helpers

  before do
    @extensions = Sensu::Extensions.new
  end

  it 'can load the default extensions' do
    expect(@extensions).to respond_to(:[], :mutator_exists?, :handler_exists?)
    expect(@extensions[:mutators]).to be_kind_of(Hash)
    expect(@extensions[:mutators]).to be_empty
    expect(@extensions[:handlers]).to be_kind_of(Hash)
    expect(@extensions[:handlers]).to be_empty
    @extensions.load_all
    expect(@extensions[:mutators]['only_check_output']).to be_an_instance_of(Sensu::Extension::OnlyCheckOutput)
    expect(@extensions[:handlers]['debug']).to be_an_instance_of(Sensu::Extension::Debug)
  end

  it 'can load custom extensions and ignore those with syntax errors' do
    @extensions.require_directory(options[:extension_dir])
    @extensions.load_all
    @extensions.mutator_exists?('opentsdb')
    expect(@extensions[:mutators]['opentsdb']).to be_an_instance_of(Sensu::Extension::OpenTSDB)
  end

  it 'can stop all extensions for cleanup purposes' do
    @extensions.load_all
    stopped_all = false
    @extensions.stop_all do
      stopped_all = true
    end
    expect(stopped_all).to be_true
  end
end
