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
    expect(redacted[:one]).to eq(1)
    expect(redacted[:password]).to eq('REDACTED')
    expect(redacted[:nested][:password]).to eq('REDACTED')
    expect(redacted[:diff_one][1][:secret]).to eq('REDACTED')
    expect(redacted[:diff_two][0][:secret]).to eq('REDACTED')
    expect(redacted[:diff_two][1][:secret]).to eq('REDACTED')
  end
end
