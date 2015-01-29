require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/socket'
require 'json'

describe Sensu::Socket do
  include Helpers

  before(:each) do
    MultiJson.load_options = {:symbolize_keys => true}
  end

  subject { described_class.new(nil) }

  let(:logger) { double('Logger') }
  let(:transport) { double('Transport') }

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

  describe '#validate_check_result' do
    shared_examples_for "a validator" do |description, overlay, error_message|
      it description do
        invalid_check = result_template[:check].merge!(overlay)
        expect { subject.validate_check_result(invalid_check) }.to \
          raise_error(described_class::DataError, error_message)
      end
    end

    it_should_behave_like 'a validator',
      'must contain a non-empty',
      {:name => ''},
      'check name must be a string and cannot contain spaces or special characters'

    it_should_behave_like 'a validator',
      'must contain an acceptable check name',
      {:name => 'check name'},
      'check name must be a string and cannot contain spaces or special characters'

    it_should_behave_like 'a validator',
      'must have check output that is a string',
      {:output => 1234},
      'check output must be a string'

    it_should_behave_like 'a validator',
      'must have an integer status',
      {:status => '2'},
      'check status must be an integer'
  end

  describe '#publish_check_result' do
    it 'publishes check result' do
      check_result = result_template
      expect(logger).to receive(:info).
        with('publishing check result', {:payload => check_result})
      expect(transport).to receive(:publish).
        with(:direct, 'results', kind_of(String)) do |_, _, json_string|
          expect(MultiJson.load(json_string)).to eq(check_result)
        end
      subject.publish_check_result(check_result[:check])
    end
  end

  describe '#process_check_result' do
    it 'rejects invalid check results' do
      invalid_check = result_template[:check].merge(:status => "2")
      expect { subject.process_check_result(invalid_check) }.to \
        raise_error(described_class::DataError)
    end

    it 'publishes valid check results' do
      check = result_template[:check]
      expect(subject).to receive(:validate_check_result).with(check)
      expect(subject).to receive(:publish_check_result).with(check)
      subject.protocol = :udp
      subject.process_check_result(check)
    end
  end

  describe '#parse_check_result' do
    it 'rejects invalid json' do
      subject.protocol = :udp
      expect { subject.parse_check_result('{"invalid"') }.to \
        raise_error(JSON::ParserError)
    end

    it 'cancels connection watchdog and processes valid json' do
      check = result_template[:check]
      json_check_data = MultiJson.dump(check)
      expect(subject).to receive(:cancel_watchdog)
      expect(subject).to receive(:process_check_result).with(check)
      subject.parse_check_result(json_check_data)
    end
  end

  describe '#process_data' do
    it 'detects non-ASCII characters' do
      expect(logger).to receive_messages(:warn => 'socket received non-ascii characters')
      expect(subject).to receive(:respond).with('invalid')
      subject.process_data("\x80\x88\x99\xAA\xBB")
    end

    it 'responds to a `ping`' do
      expect(logger).to receive_messages(:debug => 'socket received ping')
      expect(subject).to receive(:respond).with('pong')
      subject.process_data('ping')
    end

    it 'responds to a `  ping  `' do
      expect(logger).to receive_messages(:debug => 'socket received ping')
      expect(subject).to receive(:respond).with('pong')
      subject.process_data('  ping  ')
    end

    it 'debug-logs data chunks passing through it' do
      data = 'a relentless stream'
      expect(logger).to receive(:debug).
        with('socket received data', :data => data)
      expect(subject).to receive(:parse_check_result).with(data)
      subject.process_data(data)
    end
  end

  describe '#receive_data' do
    shared_examples_for 'it receives data through an eventmachine tcp socket server' do
      it 'does so successfully' do
        MultiJson.use(adapter)
        async_wrapper do
          EM.start_server('127.0.0.1', 3030, described_class) do |socket|
            socket.logger = logger
            socket.settings = settings
            socket.transport = transport
            expect(socket).to receive(:respond).with('ok') do
              timer(described_class::WATCHDOG_DELAY * 1.1) do
                async_done
              end
            end
          end
          expect(logger).not_to receive(:warn)
          expect(logger).not_to receive(:error)
          expect(logger).to receive(:debug).
            with('socket received data', kind_of(Hash)).at_least(:once)
          expect(logger).to receive(:info).
            with('publishing check result', {:payload => check_result})
          expect(transport).to receive(:publish).
            with(:direct, 'results', kind_of(String)) do |_, _, json_string|
              expect(MultiJson.load(json_string)).to eq(check_result)
            end
          timer(0.1) do
            EM.connect('127.0.0.1', 3030) do |socket|
              EM.tick_loop do
                if data.empty?
                  :stop
                else
                  socket.send_data(data.shift)
                end
              end
            end
          end
        end
      end
    end

    context 'when using different JSON adapters' do
      let(:check_result) { result_template }

      describe 'when using the basic JSON gem to process data' do
        let(:adapter) { :json_gem }
        let(:data) { MultiJson.dump(check_result[:check]).chars.to_a }

        it_behaves_like 'it receives data through an eventmachine tcp socket server'
      end

      describe 'when using Yajl to process data' do
        let(:adapter) { :yajl }
        let(:data) do
          ["{\"name\":\"te", "st\",\"command\":\"echo WARNING && exit 1\",\"issued\":1234,\"output\":\"WARNING\",\"status\":1}"]
        end

        it_behaves_like 'it receives data through an eventmachine tcp socket server'
      end
    end

    it 'allows incremental receipt of data for tcp connections' do
      check_result = result_template
      expect(logger).to receive(:info).with('publishing check result', {:payload => check_result})
      expect(subject).to receive(:respond).with('ok')
      expect(transport).to receive(:publish).
        with(:direct, 'results', kind_of(String)) do |_, _, json_string|
          expect(MultiJson.load(json_string)).to eq(check_result)
        end
      json_check_data = MultiJson.dump(check_result[:check])
      json_check_data.chars.each_with_index do |char, index|
        expect(logger).to receive(:debug).with("socket received data", :data => json_check_data[0..index])
        subject.receive_data(char)
      end
    end

    it 'will discard data from a sender that has stopped sending for too long' do
      async_wrapper do
        EM::start_server('127.0.0.1', 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          expect(socket).to receive(:respond).with('invalid') do
            async_done
          end
        end
        allow(logger).to receive(:debug)
        expect(logger).to receive(:warn).
          with('discarding data buffer for sender and closing connection', kind_of(Hash))
        timer(0.1) do
          EM.connect('127.0.0.1', 3030) do |socket|
            socket.send_data('{"partial":')
          end
        end
      end
    end

    it 'receives data as part of an eventmachine udp socket server' do
      check_result = result_template
      async_wrapper do
        EM::open_datagram_socket('127.0.0.1', 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          socket.protocol = :udp
          expect(socket).to receive(:respond).with('invalid')
          expect(socket).to receive(:respond).with('ok') do
            timer(0.5) do
              async_done
            end
          end
        end
        allow(logger).to receive(:debug)
        expect(logger).to receive(:error).
          with('failed to process check result from socket', kind_of(Hash))
        expect(logger).to receive(:info).
          with('publishing check result', {:payload => check_result})
        expect(transport).to receive(:publish).
          with(:direct, 'results', kind_of(String)) do |_, _, json_string|
            expect(MultiJson.load(json_string)).to eq(check_result)
          end
        timer(0.1) do
          EM::open_datagram_socket('0.0.0.0', 0, nil) do |socket|
            socket.send_datagram('{"partial":', '127.0.0.1', 3030)
            socket.send_datagram(MultiJson.dump(check_result[:check]), '127.0.0.1', 3030)
          end
        end
      end
    end
  end
end
