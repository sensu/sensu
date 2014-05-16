require File.dirname(__FILE__) + '/../lib/sensu/base.rb'
require File.dirname(__FILE__) + '/helpers.rb'

describe 'Sensu::Extension::Base' do
  include Helpers

  it 'can run (nagios spec)' do
    extension = Sensu::Extension::Base.new
    expect(extension).to respond_to(:name, :description, :[])
    expect(extension.name).to eq('base')
    expect(extension['name']).to eq('base')
    expect(extension[:name]).to eq('base')
    expect(extension[:type]).to eq('extension')
    extension.run do |output, status|
      expect(output).to eq('noop')
      expect(status).to eq(0)
    end
  end

  it 'can clean up before the process terminates' do
    extension = Sensu::Extension::Base.new
    stopped = false
    extension.stop do
      stopped = true
    end
    expect(stopped).to be_true
  end

  it 'can determine descendants (classes)' do
    class Foo < Sensu::Extension::Base; end
    class Bar < Sensu::Extension::Base; end
    descendants = Sensu::Extension::Base.descendants
    expect(descendants).to include(Foo)
    expect(descendants).to include(Bar)
  end
end
