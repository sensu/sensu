require "sensu/api/validators"

describe "Sensu::API::Process" do
  it "can validate a client definition" do
    client = {
      :name => "i-424242",
      :address => "127.0.0.1",
      :subscriptions => ["test"]
    }
    validator = Sensu::API::Validators::Client.new
    expect(validator.valid?(client)).to be(true)
    client[:name] = 42
    expect(validator.valid?(client)).to be(false)
  end
end
