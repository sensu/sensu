require "sensu/api/utilities/filter_response_content"

describe "Sensu::API::Utilities::FilterResponseContent" do
  include Sensu::API::Utilities::FilterResponseContent

  it "can create a nested hash from a dot notation key and value" do
    hash = dot_notation_to_hash("rspec.foo.bar", 42)
    expect(hash).to eq({:rspec => {:foo => {:bar => 42}}})
  end

  it "can deep merge two hashes" do
    hash_one = {
      :foo => "foo",
      :bar => 1,
      :baz => {
        :foo => ["foo", "bar"],
        :bar => {
          :baz => "baz"
        }
      }
    }
    hash_two = {
      :foo => "foo",
      :bar => 2,
      :baz => {
        :foo => ["foo", "baz"],
        :bar => {
          :baz => "bar"
        }
      }
    }
    expected = {
      :foo => "foo",
      :bar => 2,
      :baz => {
        :foo => ["foo", "bar", "baz"],
        :bar => {
          :baz => "bar"
        }
      }
    }
    merged_hash = deep_merge(hash_one, hash_two)
    expect(merged_hash).to eq(expected)
  end

  it "can determine if attributes match an object" do
    object = {
      :foo => "foo",
      :bar => {
        :baz => "baz"
      },
      :qux => 1
    }
    attributes = {
      :foo => "foo",
      :bar => {
        :baz => "bar"
      }
    }
    expect(attributes_match?(object, attributes)).to be(false)
    attributes[:bar][:baz] = "baz"
    expect(attributes_match?(object, attributes)).to be(true)
  end
end
