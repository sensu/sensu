require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/utilities'

describe 'Sensu::Utilities' do
  include Helpers
  include Sensu::Utilities

  it 'can determine that we are testing' do
    expect(testing?).to be(true)
  end

  it 'can retry a block call until it returns true' do
    async_wrapper do
      times = 0
      retry_until_true(0.05) do
        times +=1
        times == 3
      end
      timer(0.5) do
        expect(times).to eq(3)
        async_done
      end
    end
  end

  it 'can deep merge two hashes' do
    hash_one = {
      :foo => 1,
      :bar => {
        :one => 1,
        :two => {
          :three => 3
        }
      },
      :baz => ["one"],
      :qux => 42
    }
    hash_two = {
      :foo => 42,
      :bar => {
        :one => "one",
        :two => {
          :three => 3,
          :four => 4
        }
      },
      :baz => ["one", "two", "three"],
      :qux => [42]
    }
    expected = {
      :foo => 42,
      :bar => {
        :one => "one",
        :two => {
          :three => 3,
          :four => 4
        }
      },
      :baz => ["one", "two", "three"],
      :qux => [42]
    }
    expect(deep_merge(hash_one, hash_two)).to eq(expected)
  end

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
