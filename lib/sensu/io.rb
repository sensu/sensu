module Sensu
  class IO
    class << self
      def popen(command, mode='r', timeout=nil, &block)
        block ||= Proc.new {}
        begin
          if RUBY_VERSION < '1.9.0'
            child = ::IO.popen(command + ' 2>&1', mode)
            block.call(child)
            wait_on_process(child)
          else
            child = ::IO.popen(['sh', '-c', command, :err => [:child, :out], :pgroup => true], mode)
            unless timeout.nil?
              Timeout.timeout(timeout) do
                block.call(child)
                wait_on_process(child)
              end
            else
              block.call(child)
              wait_on_process(child)
            end
          end
        rescue Timeout::Error
          begin
            ::Process.kill(9, -child.pid)
            loop do
              ::Process.wait2(-child.pid)
            end
          rescue Errno::ESRCH, Errno::ECHILD
            ['Execution timed out', 2]
          end
        rescue Errno::ENOENT => error
          [error.to_s, 127]
        rescue => error
          ['Unexpected error: ' + error.to_s, 2]
        end
      end

      private

      def wait_on_process(process)
        output = process.read
        _, status = ::Process.wait2(process.pid)
        [output, status.exitstatus]
      end
    end
  end
end
