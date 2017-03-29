require "sensu/api/validators/client"

describe "Sensu::API::Validators::Client" do
  before do
    @validator = Sensu::API::Validators::Client.new
  end

  it "can validate a client definition" do
    client = {
      :name => "i-424242",
      :address => "127.0.0.1",
      :subscriptions => ["test"]
    }
    expect(@validator.valid?(client)).to be(true)
    client[:name] = 42
    expect(@validator.valid?(client)).to be(false)
  end
end
