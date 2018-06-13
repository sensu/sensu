module Sensu
  module Server
    module Filter
      # Determine if an event handler is silenced.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @return [TrueClass, FalseClass]
      def handler_silenced?(handler, event)
        event[:silenced] && !handler[:handle_silenced]
      end

      # Determine if handling is disabled for an event. Check
      # definitions can disable event handling with an attribute,
      # `:handle`, by setting it to `false`.
      #
      # @param event [Hash]
      # @return [TrueClass, FalseClass]
      def handling_disabled?(event)
        event[:check][:handle] == false
      end

      # Determine if an event with an action should be handled. An
      # event action of `:flapping` indicates that the event state is
      # flapping, and the event should not be handled unless its
      # handler has `:handle_flapping` set to `true`.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @return [TrueClass, FalseClass]
      def handle_action?(handler, event)
        event[:action] != :flapping ||
          (event[:action] == :flapping && !!handler[:handle_flapping])
      end

      # Determine if an event with a check severity will be handled.
      # Event handlers can specify the check severities they will
      # handle, using the definition attribute `:severities`. The
      # possible severities are "ok", "warning", "critical", and
      # "unknown". Handler severity filtering is bypassed when the
      # event `:action` is `:resolve` and a previous check history
      # status identifies a severity specified in the handler
      # definition. It's possible for a check history status of 0 to
      # have had the flapping action, so we are unable to consider
      # every past 0 to indicate a resolution.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @return [TrueClass, FalseClass]
      def handle_severity?(handler, event)
        if handler.has_key?(:severities)
          case event[:action]
          when :resolve
            event[:check][:history].any? do |status|
              severity = SEVERITIES[status.to_i] || "unknown"
              handler[:severities].include?(severity)
            end
          else
            severity = SEVERITIES[event[:check][:status]] || "unknown"
            handler[:severities].include?(severity)
          end
        else
          true
        end
      end

      # Determine if a filter is to be evoked for the current time. A
      # filter can be configured with a time window defining when it
      # is to be evoked, e.g. Monday through Friday, 9-5.
      #
      # @param filter [Hash] definition.
      # @return [TrueClass, FalseClass]
      def in_filter_time_windows?(filter)
        if filter[:when]
          in_time_windows?(filter[:when])
        else
          true
        end
      end

      # Determine if an event is filtered by a native filter.
      #
      # @param filter_name [String]
      # @param event [Hash]
      # @yield [filtered] callback/block called with a single
      #   parameter to indicate if the event was filtered.
      # @yieldparam filtered [TrueClass,FalseClass] indicating if the
      #   event was filtered.
      # @yieldparam filter_name [String] name of the filter being evaluated
      def native_filter(filter_name, event)
        filter = @settings[:filters][filter_name]
        if in_filter_time_windows?(filter)
          matched = attributes_match?(event, filter[:attributes])
          yield(filter[:negate] ? matched : !matched, filter_name)
        else
          yield(false, filter_name)
        end
      end

      # Determine if an event is filtered by a filter extension.
      #
      # @param filter_name [String]
      # @param event [Hash]
      # @yield [filtered] callback/block called with a single
      #   parameter to indicate if the event was filtered.
      # @yieldparam filtered [TrueClass,FalseClass] indicating if the
      #   event was filtered.
      # @yieldparam filter_name [String] name of the filter being evaluated
      def extension_filter(filter_name, event)
        extension = @extensions[:filters][filter_name]
        if in_filter_time_windows?(extension.definition)
          extension.safe_run(event) do |output, status|
            yield(status == 0, filter_name)
          end
        else
          yield(false, filter_name)
        end
      end

      # Determine if an event is filtered by an event filter, native
      # or extension. This method first checks for the existence of a
      # native filter, then checks for an extension if a native filter
      # is not defined. The provided callback is called with a single
      # parameter, indicating if the event was filtered by a filter.
      # If a filter does not exist for the provided name, the event is
      # not filtered.
      #
      # @param filter_name [String]
      # @param event [Hash]
      # @yield [filtered] callback/block called with a single
      #   parameter to indicate if the event was filtered.
      # @yieldparam filtered [TrueClass,FalseClass] indicating if the
      #   event was filtered.
      # @yieldparam filter_name [String] name of the filter being evaluated
      def event_filter(filter_name, event)
        case
        when @settings.filter_exists?(filter_name)
          native_filter(filter_name, event) do |filtered|
            yield(filtered, filter_name)
          end
        when @extensions.filter_exists?(filter_name)
          extension_filter(filter_name, event) do |filtered|
            yield(filtered, filter_name)
          end
        else
          @logger.error("unknown filter", :filter_name => filter_name)
          yield(false, filter_name)
        end
      end

      # Determine if an event is filtered for a handler. If a handler
      # specifies one or more filters, via `:filters` or `:filter`,
      # the `event_filter()` method is called for each of them. If any
      # of the filters return `true`, the event is filtered for the
      # handler. If no filters are defined in the handler definition,
      # the event is not filtered.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @yield [filtered] callback/block called with a single
      #   parameter to indicate if the event was filtered.
      # @yieldparam filtered [TrueClass,FalseClass] indicating if the
      #   event was filtered.
      def event_filtered?(handler, event)
        if handler.has_key?(:filters) || handler.has_key?(:filter)
          filter_list = Array(handler[:filters] || handler[:filter]).dup
          filter = Proc.new do |filter_list|
            filter_name = filter_list.shift
            if filter_name.nil?
              yield(false)
            else
              event_filter(filter_name, event) do |filtered|
                filtered ? yield(true, filter_name) : EM.next_tick { filter.call(filter_list) }
              end
            end
          end
          filter.call(filter_list)
        else
          yield(false)
        end
      end

      # Attempt to filter an event for a handler. This method will
      # check to see if handling is disabled, if the event action is
      # handled, if the event check severity is handled, if the
      # handler is subdued, and if the event is filtered by any of the
      # filters specified in the handler definition.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @yield [event] callback/block called if the event has not been
      #   filtered.
      # @yieldparam event [Hash]
      def filter_event(handler, event)
        handler_info = case handler[:type]
          when "extension" then handler.definition
          else handler  
        end
        details = {:handler => handler_info, :event => event}
        filter_message = case
        when handling_disabled?(event)
          "event handling disabled for event"
        when !handle_action?(handler, event)
          "handler does not handle action"
        when !handle_severity?(handler, event)
          "handler does not handle event severity"
        when handler_silenced?(handler, event)
          "handler is silenced"
        end
        if filter_message
          @logger.info(filter_message, details)
          @in_progress[:events] -= 1 if @in_progress
        else
          event_filtered?(handler, event) do |filtered, filter_name|
            unless filtered
              yield(event)
            else
              details[:filter] = filter_name
              @logger.info("event was filtered", details)
              @in_progress[:events] -= 1 if @in_progress
            end
          end
        end
      end
    end
  end
end
