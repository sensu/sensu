require File.join(File.dirname(__FILE__), "..", "helpers.rb")

require "sensu/client/socket"

describe Sensu::Client::Socket do
  include Helpers

  subject { described_class.new(nil) }

  let(:logger) { double("Logger") }
  let(:transport) { double("Transport") }

  let(:settings) do
    {
      :client => client_template
    }
  end

  before(:each) do
    subject.logger = logger
    subject.settings = settings
    subject.transport = transport
    allow(Time).to receive_messages(:now => Time.at(1234))
  end

  describe "#validate_check_result" do
    shared_examples_for "a validator" do |description, overlay, error_message|
      it description do
        invalid_check = result_template[:check].merge!(overlay)
        expect { subject.validate_check_result(invalid_check) }.to \
          raise_error(described_class::DataError, error_message)
      end
    end

    it_should_behave_like "a validator",
      "must contain a non-empty",
      {:name => ""},
      "check name cannot contain spaces or special characters"

    it_should_behave_like "a validator",
      "must contain an acceptable check name",
      {:name => "check name"},
      "check name cannot contain spaces or special characters"

    it_should_behave_like "a validator",
      "must contain a single-line check name",
      {:name => "check\nname"},
      "check name cannot contain spaces or special characters"

    it_should_behave_like "a validator",
      "must contain an acceptable check source",
      {:source => "check source"},
      "check source cannot contain spaces, special characters, or invalid tokens"

    it_should_behave_like "a validator",
      "must contain a single-line check source",
      {:source => "check\nsource"},
      "check source cannot contain spaces, special characters, or invalid tokens"

    it_should_behave_like "a validator",
      "must have check output that is a string",
      {:output => 1234},
      "check output must be a string"

    it_should_behave_like "a validator",
      "must have an integer status",
      {:status => "2"},
      "check status must be an integer"

    it_should_behave_like "a validator",
      "must have an integer executed timestamp",
      {:executed => "1431361723"},
      "check executed timestamp must be an integer"

    it_should_behave_like "a validator",
      "check ttl must be an integer if set",
      {:ttl => "30"},
      "check ttl must be an integer"

    it_should_behave_like "a validator",
      "check ttl must be an integer greater than 0 if set",
      {:ttl => -10},
      "check ttl must be greater than 0"

    it_should_behave_like "a validator",
      "check low flap threshold must be an integer if set",
      {:low_flap_threshold => "20"},
      "check low flap threshold must be an integer"
  end

  describe "#publish_check_result" do
    it "publishes check result" do
      check_result = result_template
      expect(logger).to receive(:info).
        with("publishing check result", {:payload => check_result})
      expect(transport).to receive(:publish).
        with(:direct, "results", kind_of(String)) do |_, _, json_string|
          expect(Sensu::JSON.load(json_string)).to eq(check_result)
        end
      subject.publish_check_result(check_result[:check])
    end

    it "publishes check result with client signature" do
      subject.settings[:client][:signature] = "foo"
      check_result = result_template
      check_result[:signature] = "foo"
      expect(logger).to receive(:info).
        with("publishing check result", {:payload => check_result})
      expect(transport).to receive(:publish).
        with(:direct, "results", kind_of(String)) do |_, _, json_string|
          expect(Sensu::JSON.load(json_string)).to eq(check_result)
        end
      subject.publish_check_result(check_result[:check])
    end
  end

  describe "#process_check_result" do
    it "rejects invalid check results" do
      invalid_check = result_template[:check].merge(:status => "2")
      expect { subject.process_check_result(invalid_check) }.to \
        raise_error(described_class::DataError)
    end

    it "publishes valid check results" do
      check = result_template[:check]
      expect(subject).to receive(:validate_check_result).with(check)
      expect(subject).to receive(:publish_check_result).with(check)
      subject.protocol = :udp
      subject.process_check_result(check)
    end
  end

  describe "#parse_check_result" do
    it "rejects invalid json" do
      subject.protocol = :udp
      expect { subject.parse_check_result('{"invalid"') }.to \
        raise_error(Sensu::JSON::ParseError)
    end

    it "cancels connection watchdog and processes valid json" do
      check = result_template[:check]
      json_check_data = Sensu::JSON.dump(check)
      expect(subject).to receive(:cancel_watchdog)
      expect(subject).to receive(:process_check_result).with(check)
      expect(subject).to receive(:respond).with("ok")
      subject.parse_check_result(json_check_data)
    end

    it "accepts also non-ASCII characters" do
      json_check_data = "{\"name\":\"test\", \"output\":\"\u3042\u4e9c\u5a40\"}"
      check = {:name => "test", :output => "\u3042\u4e9c\u5a40"}
      expect(subject).to receive(:cancel_watchdog)
      expect(subject).to receive(:process_check_result).with(check)
      expect(subject).to receive(:respond).with("ok")
      subject.parse_check_result(json_check_data)
    end
    
    it "also accepts multiple check results" do
      json_check_data = "[{\"name\": \"test1\", \"output\": \"good!\"},
                          {\"name\": \"test2\", \"output\": \"still good!\"}]"
      checks = [{:name => "test1", :output => "good!"},
                {:name => "test2", :output => "still good!"}]
      expect(subject).to receive(:cancel_watchdog)
      len = checks.length-1
      for i in (0..len) do
        expect(subject).to receive(:process_check_result).with(checks[i])
      end
      expect(subject).to receive(:respond).with("ok")
      subject.parse_check_result(json_check_data)
    end
    
  end

  describe "#process_data" do
    it "responds to a `ping`" do
      expect(logger).to receive_messages(:debug => "socket received ping")
      expect(subject).to receive(:respond).with("pong")
      subject.process_data("ping")
    end

    it "responds to a `  ping  `" do
      expect(logger).to receive_messages(:debug => "socket received ping")
      expect(subject).to receive(:respond).with("pong")
      subject.process_data("  ping  ")
    end

    it "debug-logs data chunks passing through it" do
      data = "a relentless stream"
      expect(logger).to receive(:debug).
        with("socket received data", :data => data)
      expect(subject).to receive(:parse_check_result).with(data)
      subject.process_data(data)
    end

    it "accepts also non-ASCII characters" do
      data = "{\"data\":\"\u3042\u4e9c\u5a40\"}"
      expect(logger).to receive(:debug).
        with("socket received data", :data => data)
      expect(subject).to receive(:parse_check_result).with(data)
      subject.process_data(data)
    end

    it "warn-logs encoding error" do
      # contains invalid sequence as UTF-8
      data = "{\"data\":\"\xc2\x7f\"}"
      expect(logger).to receive(:debug).
        with("socket received data", :data => data)
      expect(logger).to receive(:warn).
        with("data from socket is not a valid UTF-8 sequence, processing it anyways", :data => data)
      expect(subject).to receive(:parse_check_result).with(data)
      subject.process_data(data)
    end
  end

  describe "#receive_data" do
    it "allows incremental receipt of data for tcp connections" do
      check_result = result_template
      expect(logger).to receive(:info).with("publishing check result", {:payload => check_result})
      expect(subject).to receive(:respond).with("ok")
      expect(transport).to receive(:publish).
        with(:direct, "results", kind_of(String)) do |_, _, json_string|
          expect(Sensu::JSON.load(json_string)).to eq(check_result)
        end
      json_check_data = Sensu::JSON.dump(check_result[:check])
      json_check_data.chars.each_with_index do |char, index|
        expect(logger).to receive(:debug).with("socket received data", :data => json_check_data[0..index])
        subject.receive_data(char)
      end
    end

    it "receives data as part of an eventmachine tcp socket server" do
      check_result = result_template
      async_wrapper do
        EM.start_server("127.0.0.1", 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          expect(socket).to receive(:respond).with("ok") do
            timer(described_class::WATCHDOG_DELAY * 1.1) do
              async_done
            end
          end
        end
        expect(logger).not_to receive(:warn)
        expect(logger).not_to receive(:error)
        expect(logger).to receive(:debug).
          with("socket received data", kind_of(Hash)).at_least(:once)
        expect(logger).to receive(:info).
          with("publishing check result", {:payload => check_result})
        expect(transport).to receive(:publish).
          with(:direct, "results", kind_of(String)) do |_, _, json_string|
            expect(Sensu::JSON.load(json_string)).to eq(check_result)
          end
        timer(0.1) do
          EM.connect("127.0.0.1", 3030) do |socket|
            # send data one byte at a time.
            pending = Sensu::JSON.dump(check_result[:check]).chars.to_a
            EM.tick_loop do
              if pending.empty?
                :stop
              else
                socket.send_data(pending.shift)
              end
            end
          end
        end
      end
    end

    it "will discard data from a sender that has stopped sending for too long" do
      async_wrapper do
        EM::start_server("127.0.0.1", 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          expect(socket).to receive(:respond).with("invalid") do
            async_done
          end
        end
        allow(logger).to receive(:debug)
        expect(logger).to receive(:warn).
          with("discarding data buffer for sender and closing connection", kind_of(Hash))
        timer(0.1) do
          EM.connect("127.0.0.1", 3030) do |socket|
            socket.send_data('{"partial":')
          end
        end
      end
    end

    it "receives data as part of an eventmachine udp socket server" do
      check_result = result_template
      async_wrapper do
        EM::open_datagram_socket("127.0.0.1", 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          socket.protocol = :udp
          expect(socket).to receive(:respond).with("invalid")
          expect(socket).to receive(:respond).with("ok") do
            timer(0.5) do
              async_done
            end
          end
        end
        allow(logger).to receive(:debug)
        expect(logger).to receive(:error).
          with("failed to process check result from socket", kind_of(Hash))
        expect(logger).to receive(:info).
          with("publishing check result", {:payload => check_result})
        expect(transport).to receive(:publish).
          with(:direct, "results", kind_of(String)) do |_, _, json_string|
            expect(Sensu::JSON.load(json_string)).to eq(check_result)
          end
        timer(0.1) do
          EM::open_datagram_socket("0.0.0.0", 0, nil) do |socket|
            socket.send_datagram('{"partial":', "127.0.0.1", 3030)
            socket.send_datagram(Sensu::JSON.dump(check_result[:check]), "127.0.0.1", 3030)
          end
        end
      end
    end
  end
end
