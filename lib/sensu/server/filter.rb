require "sensu/sandbox"

module Sensu
  module Server
    module Filter
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

      def subdue_days?(condition)
        if condition.has_key?(:days)
          days = condition[:days].map(&:downcase)
          days.include?(Time.now.strftime("%A").downcase)
        else
          false
        end
      end

      def subdue_exception?(condition)
        if condition.has_key?(:exceptions)
          condition[:exceptions].any? do |exception|
            Time.now >= Time.parse(exception[:begin]) && Time.now <= Time.parse(exception[:end])
          end
        else
          false
        end
      end

      def action_subdued?(condition)
        subdued = subdue_time?(condition) || subdue_days?(condition)
        subdued && !subdue_exception?(condition)
      end

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

      def check_request_subdued?(check)
        if check[:subdue] && check[:subdue][:at] == "publisher"
          action_subdued?(check[:subdue])
        else
          false
        end
      end

      def handle_action?(handler, event)
        event[:action] != :flapping ||
          (event[:action] == :flapping && handler[:handle_flapping])
      end

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

      def eval_attribute_value(raw_eval_string, value)
        begin
          eval_string = raw_eval_string.gsub(/^eval:(\s+)?/, "")
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

      def filter_attributes_match?(hash_one, hash_two)
        hash_one.all? do |key, value_one|
          value_two = hash_two[key]
          case
          when value_one == value_two
            true
          when value_one.is_a?(Hash) && value_two.is_a?(Hash)
            filter_attributes_match?(value_one, value_two)
          when value_one.is_a?(String) && value_one.start_with?("eval:")
            eval_attribute_value(value_one, value_two)
          else
            false
          end
        end
      end

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

      def event_filtered?(handler, event, &callback)
        if handler.has_key?(:filters) || handler.has_key?(:filter)
          filter_list = Array(handler[:filters] || handler[:filter])
          filter_results = EM::Iterator.new(filter_list)
          run_filters = Proc.new do |filter_name, iterator|
            event_filter(filter_name, event) do |filtered|
              iterator.return(filtered)
            end
          end
          filtered = Proc.new do |results|
            callback.call(results.any?)
          end
          filter_results.map(run_filters, filtered)
        else
          callback.call(false)
        end
      end

      def filter_event(handler, event, &callback)
        details = {:handler => handler, :event => event}
        if !handle_action?(handler, event)
          @logger.info("handler does not handle action", details)
        elsif !handle_severity?(handler, event)
          @logger.info("handler does not handle event severity", details)
        elsif handler_subdued?(handler, event)
          @logger.info("handler is subdued", details)
        else
          event_filtered?(handler, event) do |filtered|
            unless filtered
              callback.call(event)
            else
              @logger.info("event was filtered", details)
            end
          end
        end
      end
    end
  end
end
