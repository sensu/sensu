module Sensu
  module Extension
    class SensuGCMetrics < Check
      def name
        'sensu_gc_metrics'
      end

      def description
        'returns json formatted sensu ruby garbage collection metrics'
      end

      def definition
        {
          :type => 'metric',
          :name => name,
          :standalone => true,
          :interval => 1
        }
      end

      def run
        metrics = Hash.new
        if RUBY_VERSION >= '1.9.3'
          unless GC::Profiler.enabled?
            GC::Profiler.enable
          end
          report = GC::Profiler.result.split("\n")
          invocations = report.empty? ? 0 : report[0].split[1]
          metrics.merge!(
            :profiler => {
              :invocations => invocations,
              :total_time => GC::Profiler.total_time
            }
          )
          GC::Profiler.clear
          metrics.merge!(:stat => GC.stat)
          object_counts = ObjectSpace.count_objects.map do |key, value|
            [key.to_s.gsub(/^T_/, ''), value]
          end
          metrics.merge!(:count => Hash[object_counts])
        end
        yield(Sensu::JSON.dump(metrics), 0)
      end
    end
  end
end
