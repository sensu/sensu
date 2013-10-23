require File.dirname(__FILE__) + '/../lib/sensu/utilities.rb'

describe 'Sensu::Utilities' do
  include Sensu::Utilities

  it 'can redact sensitive info from a hash' do
    hash = {
      :one => 1,
      :password => 'foo',
      :nested => {
        :password => 'bar'
      },
      :diff_one => [nil, {:secret => 'baz'}],
      :diff_two => [{:secret => 'baz'}, {:secret => 'qux'}]
    }
    redacted = redact_sensitive(hash)
    redacted[:one].should eq(1)
    redacted[:password].should eq('REDACTED')
    redacted[:nested][:password].should eq('REDACTED')
    redacted[:diff_one][1][:secret].should eq('REDACTED')
    redacted[:diff_two][0][:secret].should eq('REDACTED')
    redacted[:diff_two][1][:secret].should eq('REDACTED')
  end
end
