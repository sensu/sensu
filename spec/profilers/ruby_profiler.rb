require 'ruby-prof'

module Sensu
  module Extension
    class RubyProfiler < Profiler
      def name
        'ruby_profiler'
      end

      def description
        'uses ruby-prof to profile sensu'
      end

      def post_init
        @report_path = '/tmp/ruby_profiler.html'
        RubyProf.start
      end

      def stop
        print = Proc.new do
          report = RubyProf.stop
          printer = RubyProf::GraphHtmlPrinter.new(report)
          File.open(@report_path, 'w') do |file|
            printer.print(file, {
              :print_file => true,
              :min_percent => 10
            })
          end
        end
        complete = Proc.new do
          @logger.info('generated html profile report', {
            :path => @report_path
          })
          yield
        end
        EM::defer(print, complete)
      end
    end
  end
end
