require 'sensu/daemon'
require 'sensu/socket'
require 'sensu/agent'

module Sensu
  class Agents
    include Daemon

    def self.run(options={})
      agents = self.new(options)
      EM::run do
        agents.start
        agents.setup_signal_traps
      end
    end # self.run

    def initialize(options={})
      super
      @state = :initialized
    end # initialize

    def start
      setup_transport
      setup_sockets
      setup_agents
      start_agents
      @state = :running
    end # start

    def pause
      unless @state == :pausing || @state == :paused
        @state = :pausing
        @agents.each { |agent| agent.pause }
        @transport.unsubscribe
        @state = :paused
      end
    end # pause

    def resume
      retry_until_true(1) do
        if @state == :paused
          if @transport.connected?
            start_agents
            true
          end
        end
      end
    end # resume

    def stop
      @logger.warn('stopping')
      pause
      @state = :stopping
      @agents.each { |agent| agent.stop }
      @transport.close
      super
    end # stop

    private

    def setup_agents
      @agents = []
      @settings.agents.each do |agent|
        @agents << Agent.new(agent, @settings[:checks], @extensions, @transport, @logger, testing?)
      end
    end

    def start_agents
      @agents.each { |agent| agent.start }
    end # start_agents

    def setup_sockets
      options = @settings[:agents][:socket] || Hash.new
      options[:bind] ||= '127.0.0.1'
      options[:port] ||= 3031
      @logger.debug('binding agent tcp and udp sockets', {
        :options => options
      })
      EM::start_server(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
      end
      EM::open_datagram_socket(options[:bind], options[:port], Socket) do |socket|
        socket.logger = @logger
        socket.settings = @settings
        socket.transport = @transport
        socket.protocol = :udp
      end
    end # setup_sockets
  end
end
