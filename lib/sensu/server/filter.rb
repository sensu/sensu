require "sensu/server/sandbox"

module Sensu
  module Server
    module Filter
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

      # Ruby eval() a string containing an expression, within the
      # scope/context of a sandbox. This method is for filter
      # attribute values starting with "eval:", with the Ruby
      # expression following the colon. A single variable is provided
      # to the expression, `value`, equal to the corresponding event
      # attribute value. The expression is expected to return a
      # boolean value.
      #
      # @param raw_eval_string [String] containing the Ruby
      #   expression to be evaluated.
      # @param value [Object] of the corresponding event attribute.
      # @return [TrueClass, FalseClass]
      def eval_attribute_value(raw_eval_string, value)
        begin
          eval_string = raw_eval_string.gsub(/\Aeval:(\s+)?/, "")
          !!Sandbox.eval(eval_string, value)
        rescue => error
          @logger.error("filter attribute eval error", {
            :raw_eval_string => raw_eval_string,
            :value => value,
            :error => error.to_s
          })
          false
        end
      end

      # Determine if all filter attribute values match those of the
      # corresponding event attributes. Attributes match if the value
      # objects are equivalent, are both hashes with matching
      # key/value pairs (recursive), have equal string values, or
      # evaluate to true (Ruby eval).
      #
      # @param hash_one [Hash]
      # @param hash_two [Hash]
      # @return [TrueClass, FalseClass]
      def filter_attributes_match?(hash_one, hash_two)
        hash_one.all? do |key, value_one|
          value_two = hash_two[key]
          case
          when value_one == value_two
            true
          when value_one.is_a?(Hash) && value_two.is_a?(Hash)
            filter_attributes_match?(value_one, value_two)
          when hash_one[key].to_s == hash_two[key].to_s
            true
          when value_one.is_a?(String) && value_one.start_with?("eval:")
            eval_attribute_value(value_one, value_two)
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
      # @param callback [Proc]
      def event_filter(filter_name, event, &callback)
        case
        when @settings.filter_exists?(filter_name)
          filter = @settings[:filters][filter_name]
          matched = filter_attributes_match?(filter[:attributes], event)
          callback.call(filter[:negate] ? matched : !matched)
        when @extensions.filter_exists?(filter_name)
          extension = @extensions[:filters][filter_name]
          extension.safe_run(event) do |output, status|
            callback.call(status == 0)
          end
        else
          @logger.error("unknown filter", :filter_name => filter_name)
          callback.call(false)
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
      # @param callback [Proc]
      def event_filtered?(handler, event, &callback)
        if handler.has_key?(:filters) || handler.has_key?(:filter)
          filter_list = Array(handler[:filters] || handler[:filter])
          filter = Proc.new do |filter_list|
            filter_name = filter_list.shift
            if filter_name.nil?
              callback.call(false)
            else
              event_filter(filter_name, event) do |filtered|
                filtered ? callback.call(true) : EM.next_tick { filter.call(filter_list) }
              end
            end
          end
          EM.next_tick { filter.call(filter_list) }
        else
          callback.call(false)
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
      # @param callback [Proc]
      def filter_event(handler, event, &callback)
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
          @handling_event_count -= 1 if @handling_event_count
        else
          event_filtered?(handler, event) do |filtered|
            unless filtered
              callback.call(event)
            else
              @logger.info("event was filtered", details)
              @handling_event_count -= 1 if @handling_event_count
            end
          end
        end
      end
    end
  end
end
