require 'helpers'
require 'multi_json'
require 'sensu/socket'

describe Sensu::Socket do
  include Helpers

  before(:each) do
    MultiJson.load_options = {:symbolize_keys => true}
  end

  subject { described_class.new(nil) }

  let(:logger) { double('Logger') }
  let(:transport) { double('Transport') }
  let(:check_result_data) do
    {
      :name => 'check_name',
      :output => 'TEST OUTPUT' * 2,
      :status => 3
    }
  end

  let(:settings) do
    {
      :client => {
        :name => 'client_name'
      }
    }
  end

  before(:each) do
    subject.logger = logger
    subject.settings = settings
    subject.transport = transport
    allow(Time).to receive_messages(:now => Time.at(1234))
  end

  describe '#receive_data' do
    it 'allows incremental receipt of data' do
      payload = {:client => 'client_name', :check => check_result_data.merge(:issued => 1234)}
      expect(logger).to receive(:info).with('publishing check result', {:payload => payload})
      expect(subject).to receive(:respond).with('ok')
      expect(transport).to receive(:publish).
        with(:direct, 'results', kind_of(String)) do |_, _, json_string|
          expect(MultiJson.load(json_string)).to eq payload
        end
      json_check_result_data = MultiJson.dump(check_result_data)
      json_check_result_data.chars.each_with_index do |char, index|
        expect(logger).to receive(:debug).with("socket received data", :data => json_check_result_data[0..index])
        subject.receive_data(char)
      end
    end

    it 'accepts data as part of an EventMachine socket server' do
      async_wrapper do
        EM.start_server('127.0.0.1', 303031, described_class) do |agent_socket|
          agent_socket.logger = logger
          agent_socket.settings = settings
          agent_socket.transport = transport
          expect(agent_socket).to receive(:respond).
            with('ok') do
              after_watchdog_should_have_fired = 1.1 * described_class::WATCHDOG_DELAY
              timer(after_watchdog_should_have_fired) { async_done}
            end
        end
        expect(logger).not_to receive(:warn)
        expect(logger).to receive(:debug).with("socket received data", kind_of(Hash)).at_least(:once)
        payload = {:client => 'client_name', :check => check_result_data.merge(:issued => 1234)}
        expect(logger).to receive(:info).
          with('publishing check result', {:payload => payload})
        expect(transport).to receive(:publish).
          with(:direct, 'results', kind_of(String)) do |_, _, json_string|
            expect(MultiJson.load(json_string)).to eq payload
          end
        timer(0.1) do
          EM.connect('127.0.0.1', 303031) do |socket|
            # Send data one byte at a time.
            pending = MultiJson.dump(check_result_data).chars.to_a
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

    it 'will give up on receiving data from a sender that has stopped sending for too long' do
      async_wrapper do
        EM::start_server('127.0.0.1', 303030, described_class) do |agent_socket|
          agent_socket.logger = logger
          agent_socket.settings = settings
          agent_socket.transport = transport
          expect(agent_socket).to receive(:respond).with('invalid') { async_done }
        end
        allow(logger).to receive(:debug)
        expect(logger).to receive(:warn).
          with('discarding data buffer for sender and closing connection', kind_of(Hash))
        timer(0.1) do
          EM.connect('127.0.0.1', 303030) do |socket|
            socket.send_data(%({"partial":))
          end
        end
      end
    end
  end

  describe '#process_data' do
    it 'detects non-ASCII characters' do
      expect(logger).to receive_messages(:warn => 'socket received non-ascii characters')
      subject.protocol = :udp
      subject.process_data("\x80\x88\x99\xAA\xBB")
    end

    it 'responds to a `ping`' do
      expect(logger).to receive_messages(:debug => 'socket received ping')
      expect(subject).to receive_messages(:respond => 'pong')
      subject.process_data('ping')
    end

    it 'responds to a `  ping  `' do
      expect(logger).to receive_messages(:debug => 'socket received ping')
      expect(subject).to receive_messages(:respond => 'pong')
      subject.process_data('  ping  ')
    end

    it 'debug-logs data blobs passing through it' do
      expect(logger).to receive(:debug).
        with('socket received data', :data => 'a relentless stream')
      subject.process_data('a relentless stream')
    end
  end

  describe '#process_check_result' do
    it 'rejects invalid check results' do
      invalid_check_result = check_result_data.merge(:status => "2")
      expect { subject.process_check_result(invalid_check_result) }.to raise_error(described_class::DataError)
    end

    it 'publishes valid check results' do
      expect(subject).to receive(:validate_check_result).with(check_result_data)
      expect(subject).to receive(:publish_check_result).with(check_result_data)
      subject.protocol = :udp
      subject.process_check_result(check_result_data)
    end
  end

  describe '#publish_check_result' do
    it 'publishes check result' do
      payload = {:client => 'client_name', :check => {:name => 'foo', :issued => 1234}}
      expect(logger).to receive(:info).with('publishing check result', {:payload => payload})
      expect(transport).to receive(:publish).with(:direct, 'results', payload.to_json)
      subject.publish_check_result({:name => 'foo'})
    end
  end

  describe '#validate_check_result' do
    shared_examples_for "a validator" do |description, overlay, error_message|
      it description do
        check_result_data.merge!(overlay)
        expect { subject.validate_check_result(check_result_data) }.to \
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
end
