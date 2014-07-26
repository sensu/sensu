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
      :status => 0,
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

  it 'detects non-ASCII characters' do
    expect(logger).to receive_messages(:warn => 'socket received non-ascii characters')
    expect(subject).to receive_messages(:respond => 'invalid')

    subject.receive_data("\x80\x88\x99\xAA\xBB")
  end

  it 'responds to a `ping`' do
    expect(logger).to receive_messages(:debug => 'socket received ping')
    expect(subject).to receive_messages(:respond => 'pong')

    subject.receive_data('  ping  ')
  end

  context 'data' do
    it 'must be valid json' do
      expect(logger).to receive(:debug).with('socket received data', :data => 'a relentless stream of garbage' )
      expect(logger).to receive(:warn).with('check result must be valid json', kind_of(Hash))

      expect(subject).to receive(:respond).with('invalid')

      subject.receive_data('a relentless stream of garbage')
    end

    it 'is validated as a check' do
      check_report_data.delete(:output)

      expect(logger).to receive(:debug).with('socket received data', { :data => check_report_data.to_json })
      expect(logger).to receive(:warn).with('invalid check result', { :check => check_report_data.merge(:issued => 1234) })

      expect(subject).to receive(:respond).with('invalid')

      subject.receive_data(check_report_data.to_json)
    end

    it 'publishes valid check results' do
      payload = {
        :payload => {
          :client => 'example_client_name',
          :check => check_report_data.merge(:issued => 1234),
        },
      }

      expect(logger).to receive(:debug).with('socket received data', { :data => check_report_data.to_json })

      expect(logger).to receive(:info)\
        .with(
          'publishing check result',
          payload
        )

      expect(transport).to receive(:publish)\
        .with(
          :direct,
          'results',
          payload.fetch(:payload).to_json
        )

      expect(subject).to receive(:respond).with('ok')

      subject.receive_data(check_report_data.to_json)
    end
  end
end
