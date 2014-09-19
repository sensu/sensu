require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/socket'

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
  end

  describe '#receive_data' do
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

    it 'receives data as part of an eventmachine socket server' do
      check_result = result_template
      async_wrapper do
        EM.start_server('127.0.0.1', 3030, described_class) do |socket|
          socket.logger = logger
          socket.settings = settings
          socket.transport = transport
          expect(socket).to receive(:respond).with('ok') do
            timer(described_class::WATCHDOG_DELAY * 1.1) { async_done}
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
            # send data one byte at a time.
            pending = MultiJson.dump(check_result[:check]).chars.to_a
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
  end
end
