module Sensu
  module Extension
    class SensuCPUTime < Check
      def name
        'sensu_cpu_time'
      end

      def description
        'returns json formatted sensu cpu time metrics'
      end

      def definition
        {
          :type => 'metric',
          :name => name,
          :subscribers => ['test'],
          :interval => 1
        }
      end

      def run
        cpu_times = Process.times
        metrics = {
          :cpu => {
            :user => cpu_times.utime,
            :system => cpu_times.stime
          }
        }
        yield(Sensu::JSON.dump(metrics), 0)
      end
    end
  end
end
