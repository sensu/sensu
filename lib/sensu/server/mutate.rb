module Sensu
  module Server
    module Mutate
      def mutator_callback(mutator, event, &callback)
        Proc.new do |output, status|
          if status == 0
            callback.call(output)
          else
            definition = mutator.is_a?(Hash) ? mutator : mutator.definition
            @logger.error("mutator error", {
              :mutator => definition,
              :event => event,
              :output => output,
              :status => status
            })
            @handling_event_count -= 1 if @handling_event_count
          end
        end
      end

      def pipe_mutator(mutator, event, &callback)
        options = {:data => MultiJson.dump(event), :timeout => mutator[:timeout]}
        block = mutator_callback(mutator, event, &callback)
        Spawn.process(mutator[:command], options, &block)
      end

      def mutator_extension(mutator, event, &callback)
        block = mutator_callback(mutator, event, &callback)
        mutator.safe_run(event, &block)
      end

      def mutate_event(handler, event, &callback)
        mutator_name = handler[:mutator] || "json"
        case
        when @settings.mutator_exists?(mutator_name)
          mutator = @settings[:mutators][mutator_name]
          pipe_mutator(mutator, event, &callback)
        when @extensions.mutator_exists?(mutator_name)
          mutator = @extensions[:mutators][mutator_name]
          mutator_extension(mutator, event, &callback)
        else
          @logger.error("unknown mutator", {
            :mutator_name => mutator_name
          })
          @handling_event_count -= 1 if @handling_event_count
        end
      end
    end
  end
end
