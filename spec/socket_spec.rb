require 'eventmachine'
require 'json'
require 'multi_json'
require 'sensu/socket'

describe Sensu::Socket do
  before(:each) do
    MultiJson.load_options = { :symbolize_keys => true }
  end

  subject { described_class.new(nil) }

  let(:logger) { double('Logger') }
  let(:transport) { double('Transport') }
  let(:check_report_data) do
    {
      :name => 'o-hai',
      :output => 'DEADBEEF' * 2,
      :status => 3,
    }
  end

  let(:settings) do
    {
      :client => {
        :name => 'example_client_name',
      },
    }
  end

  before(:each) do
    subject.logger = logger
    subject.settings = settings
    subject.transport = transport

    allow(Time).to receive_messages(:now => Time.at(1234))
  end

  describe '#receive_data' do
    it "responds 'invalid' there is a data error detected further in the processing chain" do
      expect(subject).to receive(:process_data).with(:nonce).and_raise(described_class::DataError, "OH NOES")
      expect(logger).to receive(:warn).with('OH NOES')
      expect(subject).to receive(:respond).with('invalid')

      subject.receive_data(:nonce)
    end
  end

  describe '#process_data' do
    it 'detects non-ASCII characters' do
      expect { subject.process_data("\x80\x88\x99\xAA\xBB") }.to\
        raise_error(described_class::DataError, 'socket received non-ascii characters')
    end

    it 'responds to a `ping`' do
      expect(logger).to receive_messages(:debug => 'socket received ping')
      expect(subject).to receive_messages(:respond => 'pong')

      subject.process_data('  ping  ')
    end

    it 'debug-logs data blobs passing through it' do
      expect(logger).to receive(:debug).with('socket received data', :data => 'a relentless stream of garbage' )
      expect(subject).to receive_messages(:process_json => 'a relentless stream of garbage', :respond => 'ok')

      subject.process_data('a relentless stream of garbage')
    end
  end

  describe '#process_json' do
    it 'must be valid json' do
      expect { subject.process_json('a relentless stream of garbage') }.to\
        raise_error(
          described_class::DataError,
          /check result is not valid json: error: \d+: unexpected token at 'a relentless stream of garbage'/
        )
    end

    it 'publishes valid check results' do
      expect(described_class).to receive(:validate_check_data).with(check_report_data)
      expect(subject).to receive(:publish_check_data).with(check_report_data)

      subject.process_json(check_report_data.to_json)
    end
  end

  describe '#publish_check_data' do
    it 'publishes check data' do
      payload = { :client => 'example_client_name', :check => { :o => :lol, :issued => 1234 } }

      expect(logger).to receive(:info).with('publishing check result', { :payload => payload })
      expect(transport).to receive(:publish).with(:direct, 'results', payload.to_json)

      subject.publish_check_data({:o => :lol})
    end
  end

  describe '.validate_check_data' do
    it 'must contain a non-empty check name' do
      check_report_data.merge!(:name => '')

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, "invalid check name: ''")
    end

    it 'must contain an acceptable check name' do
      check_report_data.merge!(:name => 'o hai')

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, "invalid check name: 'o hai'")
    end

    it 'must have check output that is a string' do
      check_report_data.merge!(:output => 1234)

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, 'check output must be a String, got Fixnum instead')
    end

    it 'must have an integer status' do
      check_report_data.merge!(:status => '1234')

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, 'check status must be an Integer, got String instead')
    end

    it 'must have a status code in the valid range' do
      check_report_data.merge!(:status => -2)

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, 'check status must be in {0, 1, 2, 3}, got -2 instead')

      check_report_data.merge!(:status => 4)

      expect { described_class.validate_check_data(check_report_data) }.to\
        raise_error(described_class::DataError, 'check status must be in {0, 1, 2, 3}, got 4 instead')
    end
  end
end
