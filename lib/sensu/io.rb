module Sensu
  class IO
    class << self
      def popen(command, mode='r', timeout=nil, &block)
        block ||= Proc.new {}
        begin
          if RUBY_VERSION < '1.9.3'
            child = ::IO.popen(command + ' 2>&1', mode)
            block.call(child)
            wait_on_process(child)
          else
            options = {
              :err => [:child, :out]
            }
            case RUBY_PLATFORM
            when /(ms|cyg|bcc)win|mingw|win32/
              shell = ['cmd', '/c']
              options[:new_pgroup] = true
            else
              shell = ['sh', '-c']
              options[:pgroup] = true
            end
            child = ::IO.popen(shell + [command, options], mode)
            if timeout
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
