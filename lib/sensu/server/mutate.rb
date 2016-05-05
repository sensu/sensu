module Sensu
  module Server
    module Mutate
      # Create a mutator callback (Proc). A mutator callback takes two
      # parameters, for the mutator output and status code. The
      # created callback can be used for standard mutators and mutator
      # extensions. The provided callback will only be called when the
      # mutator status is `0` (OK). If the status is not `0`, an error
      # is logged, and the `@in_progress[:events]` is decremented by
      # `1`.
      #
      # @param mutator [Object] definition or extension.
      # @param event [Hash] data.
      # @param callback [Proc] to call when the mutator status is `0`.
      # @return [Proc] mutator callback.
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
            @in_progress[:events] -= 1 if @in_progress
          end
        end
      end

      # Execute a standard mutator (pipe), spawn a process using the
      # mutator command and pipe the event data to it via STDIN. The
      # `mutator_callback()` method is used to create the mutator
      # callback, wrapping the provided callback (event handler).
      #
      # @param mutator [Hash] definition.
      # @param event [Hash] data.
      # @param callback [Proc] to call when the mutator executes
      #   successfully.
      def pipe_mutator(mutator, event, &callback)
        options = {:data => Sensu::JSON.dump(event), :timeout => mutator[:timeout]}
        block = mutator_callback(mutator, event, &callback)
        Spawn.process(mutator[:command], options, &block)
      end

      # Run a mutator extension, within the Sensu EventMachine reactor
      # (event loop). The `mutator_callback()` method is used to
      # create the mutator callback, wrapping the provided callback
      # (event handler).
      #
      # @param mutator [Object] extension.
      # @param event [Hash] data.
      # @param callback [Proc] to call when the mutator runs
      #   successfully.
      def mutator_extension(mutator, event, &callback)
        block = mutator_callback(mutator, event, &callback)
        mutator.safe_run(event, &block)
      end

      # Mutate event data for a handler. By default, the "json"
      # mutator is used, unless the handler specifies another mutator.
      # If a mutator does not exist, not defined or a missing
      # extension, an error will be logged and the
      # `@in_progress[:events]` is decremented by `1`. This method
      # first checks for the existence of a standard mutator, then
      # checks for an extension if a standard mutator is not defined.
      #
      # @param handler [Hash] definition.
      # @param event [Hash] data.
      # @param callback [Proc] to call when the mutator executes/runs
      #   successfully (event handler).
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
          @in_progress[:events] -= 1 if @in_progress
        end
      end
    end
  end
end
