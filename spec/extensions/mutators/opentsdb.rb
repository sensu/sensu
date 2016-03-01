module Sensu
  module Extension
    class OpenTSDB < Mutator
      def name
        'opentsdb'
      end

      def description
        'converts graphite plain text format to opentsdb'
      end

      def run(event)
        metrics = Array.new
        event[:check][:output].each_line do |line|
          name, value, timestamp = line.chomp.split(/\s+/)
          tags = 'check=' + event[:check][:name]
          tags += ' host=' + event[:client][:name]
          metrics << [name, timestamp, value, tags].join(' ')
        end
        yield(metrics.join("\n"), 0)
      end
    end
  end
end
