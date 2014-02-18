require 'ruby-prof'

module Sensu
  module Extension
    class RubyProfiler < Generic
      def name
        'ruby_profiler'
      end

      def description
        'uses ruby-prof to profile sensu'
      end

      def post_init
        RubyProf.start
      end

      def report_path
        '/tmp/ruby_profiler.' + ::Process.pid.to_s + '.html'
      end

      def stop
        print = Proc.new do
          result = RubyProf.stop
          printer = RubyProf::GraphHtmlPrinter.new(result)
          File.open(report_path, 'w') do |file|
            printer.print(file, {
              :print_file => true,
              :min_percent => 10
            })
          end
        end
        complete = Proc.new do
          logger.info('ruby profiler generated an html report', {
            :path => report_path
          })
          yield
        end
        EM::defer(print, complete)
      end
    end
  end
end
