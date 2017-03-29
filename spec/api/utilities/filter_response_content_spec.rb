require "sensu/api/utilities/filter_response_content"

describe "Sensu::API::Utilities::FilterResponseContent" do
  include Sensu::API::Utilities::FilterResponseContent

  it "can create a nested hash from a dot notation key and value" do
    hash = dot_notation_to_hash("rspec.foo.bar", 42)
    expect(hash).to eq({:rspec => {:foo => {:bar => 42}}})
  end

  it "can filter response content" do
    @filter_params = {
      "foo.bar.baz" => 42,
      "qux" => "rspec"
    }
    @response_content = [
      {
        :foo => {
          :bar => {
            :baz => 42
          }
        },
        :qux => "rspec"
      },
      {
        :foo => {
          :bar => {
            :baz => 42
          }
        },
        :qux => "rspec",
        :one => 1
      },
      {
        :foo => {
          :bar => {
            :baz => 42
          }
        }
      },
      {
        :qux => "rspec"
      },
      {
        :foo => {
          :bar => {
            :baz => 42
          }
        },
        :qux => "nope"
      }
    ]
    filter_response_content!
    expect(@response_content).to be_kind_of(Array)
    expect(@response_content.size).to eq(2)
  end
end
