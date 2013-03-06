require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Extension::Base' do
  include Helpers

  it 'can run (nagios spec)' do
    extension = Sensu::Extension::Base.new
    extension.should respond_to(:name, :description, :[])
    extension.name.should eq('base')
    extension['name'].should eq('base')
    extension[:name].should eq('base')
    extension[:type].should eq('extension')
    extension.run do |output, status|
      output.should eq('noop')
      status.should eq(0)
    end
  end

  it 'can clean up before the process terminates' do
    extension = Sensu::Extension::Base.new
    stopped = false
    extension.stop do
      stopped = true
    end
    stopped.should be_true
  end

  it 'can determine descendants (classes)' do
    class Foo < Sensu::Extension::Base; end
    class Bar < Sensu::Extension::Base; end
    descendants = Sensu::Extension::Base.descendants
    descendants.should include(Foo)
    descendants.should include(Bar)
  end
end
