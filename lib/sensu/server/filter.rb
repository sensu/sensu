require "sensu/server/sandbox"

module Sensu
  module Server
    module Filter
      EVAL_PREFIX = "eval:".freeze

      # Determine if a period of time (window) is subdued. The
      # provided condition must have a `:begin` and `:end` time, eg.
      # "11:30:00 PM", or `false` will be returned.
      #
      # @param condition [Hash]
      # @option condition [String] :begin time.
      # @option condition [String] :end time.
      # @return [TrueClass, FalseClass]
      def subdue_time?(condition)
        if condition.has_key?(:begin) && condition.has_key?(:end)
          begin_time = Time.parse(condition[:begin])
          end_time = Time.parse(condition[:end])
          if end_time < begin_time
            if Time.now < end_time
              begin_time = Time.parse("12:00:00 AM")
            else
              end_time = Time.parse("11:59:59 PM")
            end
          end
          Time.now >= begin_time && Time.now <= end_time
        else
          false
        end
      end

      # Determine if the current day is subdued. The provided
      # condition must have a list of `:days`, or false will be
      # returned.
      #
      # @param condition [Hash]
      # @option condition [Array] :days of the week to subdue.
      # @return [TrueClass, FalseClass]
      def subdue_days?(condition)
        if condition.has_key?(:days)
          days = condition[:days].map(&:downcase)
          days.include?(Time.now.strftime("%A").downcase)
        else
          false
        end
      end

      # Determine if there is an exception a period of time (window)
      # that is subdued. The provided condition must have an
      # `:exception`, containing one or more `:begin` and `:end`
      # times, eg. "11:30:00 PM", or `false` will be returned. If
      # there are any exceptions to a subdued period of time, `true`
      # will be returned.
      #
      # @param condition [Hash]
      # @option condition [Hash] :exceptions array of `:begin` and
      #   `:end` times.
      # @return [TrueClass, FalseClass]
      def subdue_exception?(condition)
        if condition.has_key?(:exceptions)
          condition[:exceptions].any? do |exception|
            Time.now >= Time.parse(exception[:begin]) && Time.now <= Time.parse(exception[:end])
          end
        else
          false
        end
      end

      # Determine if an action is subdued and if there is an
      # exception. This method makes use of `subdue_time?()`,
      # `subdue_days?()`, and subdue_exception?().
      #
      # @param condition [Hash]
      # @return [TrueClass, FalseClass]
      def action_subdued?(condition)
        subdued = subdue_time?(condition) || subdue_days?(condition)
        subdued && !subdue_exception?(condition)
      end

      # Determine if an event handler is subdued, by conditions set in
      # the check and/or the handler definition. If any of the
      # conditions are true, without an exception, the handler is
      # subdued.
      #
      # @param handler [Hash] definition.
      # @param event [Hash] data possibly containing subdue
      #   conditions.
      # @return [TrueClass, FalseClass]
      def handler_subdued?(handler, event)
        subdued = []
        if handler[:subdue]
          subdued << action_subdued?(handler[:subdue])
        end
        check = event[:check]
        if check[:subdue] && check[:subdue][:at] != "publisher"
          subdued << action_subdued?(check[:subdue])
        end
        subdued.any?
      end

      # Determine if a check request is subdued, by conditions set in
      # the check definition. If any of the conditions are true,
      # without an exception, the check request is subdued.
      #
      # @param check [Hash] definition.
      # @return [TrueClass, FalseClass]
      def check_request_subdued?(check)
        if check[:subdue] && check[:subdue][:at] == "publisher"
          action_subdued?(check[:subdue])
        else
          false
        end
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
      # event `:action` is `:resolve`, if the check history contains
      # one of the specified severities since the last OK result.
      #
      # @param handler [Hash] definition.
      # @param event [Hash]
      # @return [TrueClass, FalseClass]
      def handle_severity?(handler, event)
        if handler.has_key?(:severities)
          case event[:action]
          when :resolve
            event[:check][:history].reverse[1..-1].any? do |status|
              if status.to_i == 0
                break false
              end
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

      # Process a filter eval attribute, a Ruby `eval()` string
      # containing an expression to be evaluated within the
      # scope/context of a sandbox. This methods strips away the
      # expression prefix, `eval:`, and substitues any dot notation
      # tokens with the corresponding event data values. If there are
      # unmatched tokens, this method will return `nil`.
      #
      # @event [Hash]
      # @raw_eval_string [String]
      # @return [String] processed eval string.
      def process_eval_string(event, raw_eval_string)
        eval_string = raw_eval_string.slice(5..-1)
        eval_string, unmatched_tokens = substitute_tokens(eval_string, event)
        if unmatched_tokens.empty?
          eval_string
        else
          @logger.error("filter eval unmatched tokens", {
            :raw_eval_string => raw_eval_string,
            :unmatched_tokens => unmatched_tokens,
            :event => event
          })
          nil
        end
      end

      # Ruby `eval()` a string containing an expression, within the
      # scope/context of a sandbox. This method is for filter
      # attribute values starting with "eval:", with the Ruby
      # expression following the colon. A single variable is provided
      # to the expression, `value`, equal to the corresponding event
      # attribute value. Dot notation tokens in the expression, e.g.
      # `:::mysql.user:::`, are substituted with the corresponding
      # event data values prior to evaluation. The expression is
      # expected to return a boolean value.
      #
      # @param event [Hash]
      # @param raw_eval_string [String] containing the Ruby
      #   expression to be evaluated.
      # @param raw_value [Object] of the corresponding event
      #   attribute value.
      # @return [TrueClass, FalseClass]
      def eval_attribute_value(event, raw_eval_string, raw_value)
        eval_string = process_eval_string(event, raw_eval_string)
        unless eval_string.nil?
          begin
            value = Marshal.load(Marshal.dump(raw_value))
            !!Sandbox.eval(eval_string, value)
          rescue => error
            @logger.error("filter attribute eval error", {
              :event => event,
              :raw_eval_string => raw_eval_string,
              :raw_value => raw_value,
              :error => error.to_s
            })
            false
          end
        else
          false
        end
      end

      # Determine if all filter attribute values match those of the
      # corresponding event attributes. Attributes match if the value
      # objects are equivalent, are both hashes with matching
      # key/value pairs (recursive), have equal string values, or
      # evaluate to true (Ruby eval).
      #
      # @param event [Hash]
      # @param filter_attributes [Object]
      # @param event_attributes [Object]
      # @return [TrueClass, FalseClass]
      def filter_attributes_match?(event, filter_attributes, event_attributes=nil)
        event_attributes ||= event
        filter_attributes.all? do |key, value_one|
          value_two = event_attributes[key]
          case
          when value_one == value_two
            true
          when value_one.is_a?(Hash) && value_two.is_a?(Hash)
            filter_attributes_match?(event, value_one, value_two)
          when value_one.to_s == value_two.to_s
            true
          when value_one.is_a?(String) && value_one.start_with?(EVAL_PREFIX)
            eval_attribute_value(event, value_one, value_two)
          else
            false
          end
        end
      end

      # Determine if an event is filtered by an event filter, standard
      # or extension. This method first checks for the existence of a
      # standard filter, then checks for an extension if a standard
      # filter is not defined. The provided callback is called with a
      # single parameter, indicating if the event was filtered by a
      # filter. If a filter does not exist for the provided name, the
      # event is not filtered.
      #
      # @param filter_name [String]
      # @param event [Hash]
      # @yield [filtered] callback/block called with a single
      #   parameter to indicate if the event was filtered.
      # @yieldparam filtered [TrueClass,FalseClass] indicating if the
      #   event was filtered.
      def event_filter(filter_name, event)
        case
        when @settings.filter_exists?(filter_name)
          filter = @settings[:filters][filter_name]
          matched = filter_attributes_match?(event, filter[:attributes])
          yield(filter[:negate] ? matched : !matched)
        when @extensions.filter_exists?(filter_name)
          extension = @extensions[:filters][filter_name]
          extension.safe_run(event) do |output, status|
            yield(status == 0)
          end
        else
          @logger.error("unknown filter", :filter_name => filter_name)
          yield(false)
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
                filtered ? yield(true) : EM.next_tick { filter.call(filter_list) }
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
        details = {:handler => handler, :event => event}
        filter_message = case
        when handling_disabled?(event)
          "event handling disabled for event"
        when !handle_action?(handler, event)
          "handler does not handle action"
        when !handle_severity?(handler, event)
          "handler does not handle event severity"
        when handler_subdued?(handler, event)
          "handler is subdued"
        end
        if filter_message
          @logger.info(filter_message, details)
          @in_progress[:events] -= 1 if @in_progress
        else
          event_filtered?(handler, event) do |filtered|
            unless filtered
              yield(event)
            else
              @logger.info("event was filtered", details)
              @in_progress[:events] -= 1 if @in_progress
            end
          end
        end
      end
    end
  end
end
