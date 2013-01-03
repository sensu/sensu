module Sensu
  module Extension
    class OpenTSDB < Mutator
      def name
        'opentsdb'
      end

      def run(event, &block)
        begin
          metrics = Array.new
          event[:check][:output].each_line do |line|
            name, value, timestamp = line.split("\t")
            tags = 'check=' + event[:check][:name]
            tags += ' host=' + event[:client][:name]
            metrics << [name, timestamp, value, tags].join("\s")
          end
          block.call(metrics.join("\n"), 0)
        rescue => error
          block.call(error.to_s, 2)
        end
      end
    end
  end
end
