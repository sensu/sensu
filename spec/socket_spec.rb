require File.dirname(__FILE__) + '/helpers.rb'
require 'sensu/socket'

describe 'Sensu::Socket' do
  include Helpers

  before(:each) do
    MultiJson.load_options = {:symbolize_keys => true}
  end

  subject { Sensu::Socket.new(nil) }

  let(:logger) { double('Logger') }
  let(:transport) { double('Transport') }

  let(:check_result) do
    result_template
  end

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
  end
end
