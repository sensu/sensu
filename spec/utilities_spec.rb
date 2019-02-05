require File.dirname(__FILE__) + "/helpers.rb"

require "sensu/utilities"

describe "Sensu::Utilities" do
  include Helpers
  include Sensu::Utilities

  it "can determine that we are testing" do
    expect(testing?).to be(true)
  end

  it "can retry a block call until it returns true" do
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

  it "can deep merge two hashes" do
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

  it "can deeply merge a hash" do
    hash = {
      :foo => "bar",
      :baz => 1,
      :qux => false,
      :poy => ["one", "two", "three"],
      :xef => {
        :foo => "bar"
      }
    }
    expected = {
      :foo => "bar",
      :baz => 1,
      :qux => false,
      :poy => ["one", "two", "three"],
      :xef => {
        :foo => "bar"
      }
    }
    copy = deep_dup(hash)
    copy[:foo].upcase!
    copy[:poy][0].upcase!
    copy[:xef][:foo].upcase!
    expect(hash).to eq(expected)
  end

  it "can determine the system hostname" do
    hostname = system_hostname
    expect(hostname).to be_kind_of(String)
    expect(hostname).not_to be_empty
  end

  it "can determine the system address" do
    address = system_address
    expect(address).to be_kind_of(String)
    expect(address).not_to be_empty
  end

  it "can provide the process cpu times" do
    async_wrapper do
      process_cpu_times do |cpu_times|
        expect(cpu_times).to be_kind_of(Array)
        expect(cpu_times.size).to eq(4)
        expect(cpu_times.compact).not_to be_empty
        async_done
      end
    end
  end

  it "can generate a random uuid" do
    uuid = random_uuid
    expect(uuid).to be_kind_of(String)
    expect(uuid.size).to eq(36)
    expect(uuid).not_to eq(random_uuid)
  end

  it "can redact sensitive info from a hash" do
    hash = {
      :one => 1,
      :password => "foo",
      :nested => {
        :password => "bar"
      },
      :diff_one => [nil, {:secret => "baz"}],
      :diff_two => [{:secret => "baz"}, {:secret => "qux"}],
      :diff_three => [[{:secret => "jack"}], [{:secret => "jill"}]],
      :nested_str_array => [["one", "two"]]
    }
    redacted = redact_sensitive(hash)
    expect(redacted[:one]).to eq(1)
    expect(redacted[:password]).to eq("REDACTED")
    expect(redacted[:nested][:password]).to eq("REDACTED")
    expect(redacted[:diff_one][1][:secret]).to eq("REDACTED")
    expect(redacted[:diff_two][0][:secret]).to eq("REDACTED")
    expect(redacted[:diff_two][1][:secret]).to eq("REDACTED")
    expect(redacted[:diff_three][0][0][:secret]).to eq("REDACTED")
    expect(redacted[:diff_three][1][0][:secret]).to eq("REDACTED")
    expect(redacted[:nested_str_array]).to eq([["one", "two"]])
  end

  it "can substitute dot notation tokens" do
    string = ":::nested.attribute|default::: :::missing|default:::"
    string << " :::missing|::: :::missing::: :::nested.attribute:::::::nested.attribute:::"
    string << " :::empty|localhost::: :::empty.hash|localhost:8080:::"
    string << " :::foo\255|default:::"
    string << " :::empty|default|with_pipe:::"
    attributes = {
      :nested => {
        :attribute => true
      },
      :empty => {},
      :foo => true
    }
    result, unmatched_tokens = substitute_tokens(string, attributes)
    expect(result).to eq("true default   true:true localhost localhost:8080 true default|with_pipe")
    expect(unmatched_tokens).to eq(["missing"])
  end

  it "can determine if a check is subdued" do
    check = {}
    expect(check_subdued?(check)).to be(false)
    check = {
      :subdue => {
        :days => {}
      }
    }
    expect(check_subdued?(check)).to be(false)
    check[:subdue][:days][:all] = []
    expect(check_subdued?(check)).to be(false)
    check[:subdue][:days][:all] = [
      {
        :begin => (Time.now + 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 4200).strftime("%l:00 %p").strip
      }
    ]
    expect(check_subdued?(check)).to be(false)
    check[:subdue][:days][:all] = [
      {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
    ]
    expect(check_subdued?(check)).to be(true)
    check[:subdue][:days].delete(:all)
    expect(check_subdued?(check)).to be(false)
    current_day = Time.now.strftime("%A").downcase.to_sym
    check[:subdue][:days][current_day] = [
      {
        :begin => (Time.now + 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 4200).strftime("%l:00 %p").strip
      }
    ]
    expect(check_subdued?(check)).to be(false)
    check[:subdue][:days][current_day] = [
      {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
    ]
    expect(check_subdued?(check)).to be(true)
    check[:subdue][:days].delete(current_day)
    tomorrow = (Time.now + 86400).strftime("%A").downcase.to_sym
    check[:subdue][:days][tomorrow] = [
      {
        :begin => (Time.now - 3600).strftime("%l:00 %p").strip,
        :end => (Time.now + 3600).strftime("%l:00 %p").strip
      }
    ]
    expect(check_subdued?(check)).to be(false)
  end
end
