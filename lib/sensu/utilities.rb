gem "parse-cron", "0.1.4"

require "securerandom"
require "sensu/sandbox"
require "parse-cron"
require "socket"

module Sensu
  module Utilities
    EVAL_PREFIX = "eval:".freeze
    NANOSECOND_RESOLUTION = 9.freeze

    # Determine if Sensu is being tested, using the process name.
    # Sensu is being test if the process name is "rspec",
    #
    # @return [TrueClass, FalseClass]
    def testing?
      File.basename($0) == "rspec"
    end

    # Retry a code block until it retures true. The first attempt and
    # following retries are delayed.
    #
    # @param wait [Numeric] time to delay block calls.
    # @param block [Proc] to call that needs to return true.
    def retry_until_true(wait=0.5, &block)
      EM::Timer.new(wait) do
        unless block.call
          retry_until_true(wait, &block)
        end
      end
    end

    # Deep merge two hashes. Nested hashes are deep merged, arrays are
    # concatenated and duplicate array items are removed.
    #
    # @param hash_one [Hash]
    # @param hash_two [Hash]
    # @return [Hash] deep merged hash.
    def deep_merge(hash_one, hash_two)
      merged = hash_one.dup
      hash_two.each do |key, value|
        merged[key] = case
        when hash_one[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge(hash_one[key], value)
        when hash_one[key].is_a?(Array) && value.is_a?(Array)
          (hash_one[key] + value).uniq
        else
          value
        end
      end
      merged
    end

    # Creates a deep dup of basic ruby objects with support for walking
    # hashes and arrays.
    #
    # @param obj [Object]
    # @return [obj] a dup of the original object.
    def deep_dup(obj)
      if obj.class == Hash
        new_obj = obj.dup
        new_obj.each do |key, value|
          new_obj[deep_dup(key)] = deep_dup(value)
        end
        new_obj
      elsif obj.class == Array
        arr = []
        obj.each do |item|
          arr << deep_dup(item)
        end
        arr
      elsif obj.class == String
        obj.dup
      else
        obj
      end
    end

    # Retrieve the system hostname. If the hostname cannot be
    # determined and an error is thrown, `nil` will be returned.
    #
    # @return [String] system hostname.
    def system_hostname
      ::Socket.gethostname rescue nil
    end

    # Retrieve the system IP address. If a valid non-loopback
    # IPv4 address cannot be found and an error is thrown,
    # `nil` will be returned.
    #
    # @return [String] system ip address
    def system_address
      ::Socket.ip_address_list.find { |address|
        address.ipv4? && !address.ipv4_loopback?
      }.ip_address rescue nil
    end

    # Retrieve the process CPU times. If the cpu times cannot be
    # determined and an error is thrown, `[nil, nil, nil, nil]` will
    # be returned.
    #
    # @return [Array] CPU times: utime, stime, cutime, cstime
    def process_cpu_times(&callback)
      determine_cpu_times = Proc.new do
        ::Process.times.to_a rescue [nil, nil, nil, nil]
      end
      EM::defer(determine_cpu_times, callback)
    end

    # Generate a random universally unique identifier.
    #
    # @return [String] random UUID.
    def random_uuid
      ::SecureRandom.uuid
    end

    # Remove sensitive information from a hash (eg. passwords). By
    # default, hash values will be redacted for the following keys:
    # password, passwd, pass, api_key, api_token, access_key,
    # secret_key, private_key, secret
    #
    # @param obj [Object] to redact sensitive value from.
    # @param keys [Array] that indicate sensitive values.
    # @return [Hash] hash with redacted sensitive values.
    def redact_sensitive(obj, keys=nil)
      keys ||= %w[
        password passwd pass
        api_key api_token
        access_key secret_key private_key
        secret
        routing_key
        access_token_read access_token_write access_token_path
        webhook_url
        nickserv_password channel_password
        community
        keystore_password truststore_password
        proxy_password
        access_key_id secret_access_key
      ]
      obj = obj.dup
      if obj.is_a?(Hash)
        obj.each do |key, value|
          if keys.include?(key.to_s)
            obj[key] = "REDACTED"
          elsif value.is_a?(Hash) || value.is_a?(Array)
            obj[key] = redact_sensitive(value, keys)
          end
        end
      elsif obj.is_a?(Array)
        obj.map! do |item|
          if item.is_a?(Hash) || item.is_a?(Array)
            redact_sensitive(item, keys)
          else
            item
          end
        end
      end
      obj
    end

    # Traverse a hash for an attribute value, with a fallback default
    # value if nil.
    #
    # @param tree [Hash] to traverse.
    # @param path [Array] of attribute keys.
    # @param default [Object] value if attribute value is nil.
    # @return [Object] attribute or fallback default value.
    def find_attribute_value(tree, path, default)
      attribute = tree[path.shift]
      if attribute.is_a?(Hash)
        find_attribute_value(attribute, path, default)
      else
        attribute.nil? ? default : attribute
      end
    end

    # Substitute dot notation tokens (eg. :::db.name|production:::)
    # with the associated definition attribute value. Tokens can
    # provide a fallback default value, following a pipe.
    #
    # @param tokens [String]
    # @param attributes [Hash]
    # @return [Array] containing the string with tokens substituted
    #   and an array of unmatched tokens.
    def substitute_tokens(tokens, attributes)
      unmatched_tokens = []
      encoded_tokens = tokens.encode("UTF-8", "binary", {
        :invalid => :replace,
        :undef => :replace,
        :replace => ""
      })
      substituted = encoded_tokens.gsub(/:::([^:].*?):::/) do
        token, default = $1.to_s.split("|", 2)
        path = token.split(".").map(&:to_sym)
        matched = find_attribute_value(attributes, path, default)
        if matched.nil?
          unmatched_tokens << token
        end
        matched
      end
      [substituted, unmatched_tokens]
    end

    # Perform token substitution for an object. String values are
    # passed to `substitute_tokens()`, arrays and sub-hashes are
    # processed recursively. Numeric values are ignored.
    #
    # @param object [Object]
    # @param attributes [Hash]
    # @return	[Array] containing the updated object with substituted
    #   values and an array of unmatched tokens.
    def object_substitute_tokens(object, attributes)
      unmatched_tokens = []
      case object
      when Hash
        object.each do |key, value|
          object[key], unmatched = object_substitute_tokens(value, attributes)
          unmatched_tokens.push(*unmatched)
        end
      when Array
        object.map! do |value|
          value, unmatched = object_substitute_tokens(value, attributes)
          unmatched_tokens.push(*unmatched)
          value
        end
      when String
        object, unmatched_tokens = substitute_tokens(object, attributes)
      end
      [object, unmatched_tokens.uniq]
    end

    # Process an eval attribute value, a Ruby `eval()` string
    # containing an expression to be evaluated within the
    # scope/context of a sandbox. This methods strips away the
    # expression prefix, `eval:`, and substitues any dot notation
    # tokens with the corresponding event data values. If there are
    # unmatched tokens, this method will return `nil`.
    #
    # @object [Hash]
    # @raw_eval_string [String]
    # @return [String] processed eval string.
    def process_eval_string(object, raw_eval_string)
      eval_string = raw_eval_string.slice(5..-1)
      eval_string, unmatched_tokens = substitute_tokens(eval_string, object)
      if unmatched_tokens.empty?
        eval_string
      else
        @logger.error("attribute value eval unmatched tokens", {
          :object => object,
          :raw_eval_string => raw_eval_string,
          :unmatched_tokens => unmatched_tokens
        })
        nil
      end
    end

    # Ruby `eval()` a string containing an expression, within the
    # scope/context of a sandbox. This method is for attribute values
    # starting with "eval:", with the Ruby expression following the
    # colon. A single variable is provided to the expression, `value`,
    # equal to the corresponding object attribute value. Dot notation
    # tokens in the expression, e.g. `:::mysql.user:::`, are
    # substituted with the corresponding object attribute values prior
    # to evaluation. The expression is expected to return a boolean
    # value.
    #
    # @param object [Hash]
    # @param raw_eval_string [String] containing the Ruby
    #   expression to be evaluated.
    # @param raw_value [Object] of the corresponding object
    #   attribute value.
    # @return [TrueClass, FalseClass]
    def eval_attribute_value(object, raw_eval_string, raw_value)
      eval_string = process_eval_string(object, raw_eval_string)
      unless eval_string.nil?
        begin
          value = Marshal.load(Marshal.dump(raw_value))
          !!Sandbox.eval(eval_string, value)
        rescue StandardError, SyntaxError => error
          @logger.error("attribute value eval error", {
            :object => object,
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

    # Determine if all attribute values match those of the
    # corresponding object attributes. Attributes match if the value
    # objects are equivalent, are both hashes with matching key/value
    # pairs (recursive), have equal string values, or evaluate to true
    # (Ruby eval).
    #
    # @param object [Hash]
    # @param match_attributes [Object]
    # @param support_eval [TrueClass, FalseClass]
    # @param object_attributes [Object]
    # @return [TrueClass, FalseClass]
    def attributes_match?(object, match_attributes, support_eval=true, object_attributes=nil)
      object_attributes ||= object
      match_attributes.all? do |key, value_one|
        value_two = object_attributes[key]
        case
        when value_one == value_two
          true
        when value_one.is_a?(Hash) && value_two.is_a?(Hash)
          attributes_match?(object, value_one, support_eval, value_two)
        when value_one.to_s == value_two.to_s
          true
        when value_one.is_a?(String) && value_one.start_with?(EVAL_PREFIX) && support_eval
          eval_attribute_value(object, value_one, value_two)
        else
          false
        end
      end
    end

    # Determine if the current time falls within a time window. The
    # provided condition must have a `:begin` and `:end` time, eg.
    # "11:30:00 PM", or `false` will be returned.
    #
    # @param condition [Hash]
    # @option condition [String] :begin time.
    # @option condition [String] :end time.
    # @return [TrueClass, FalseClass]
    def in_time_window?(condition)
      if condition.has_key?(:begin) && condition.has_key?(:end)
        begin_time = Time.parse(condition[:begin])
        end_time = Time.parse(condition[:end])
        if end_time < begin_time
          if Time.now < end_time
            begin_time = Time.parse(*begin_time.strftime("%Y-%m-%d 00:00:00.#{Array.new(NANOSECOND_RESOLUTION, 0).join} %:z"))
          else
            end_time = Time.parse(*end_time.strftime("%Y-%m-%d 23:59:59.#{Array.new(NANOSECOND_RESOLUTION, 9).join} %:z"))
          end
        end
        Time.now >= begin_time && Time.now <= end_time
      else
        false
      end
    end

    # Determine if time window conditions for one or more days of the
    # week are met. If a day of the week is provided, it can provide
    # one or more conditions, each with a `:begin` and `:end` time,
    # eg. "11:30:00 PM", or `false` will be returned.
    #
    # @param conditions [Hash]
    # @option conditions [String] :days of the week.
    # @return [TrueClass, FalseClass]
    def in_time_windows?(conditions)
      in_window = false
      window_days = conditions[:days] || {}
      if window_days[:all]
        in_window = window_days[:all].any? do |condition|
          in_time_window?(condition)
        end
      end
      current_day = Time.now.strftime("%A").downcase.to_sym
      if !in_window && window_days[current_day]
        in_window = window_days[current_day].any? do |condition|
          in_time_window?(condition)
        end
      end
      in_window
    end

    # Determine if a check is subdued, by conditions set in the check
    # definition. If any of the conditions are true, without an
    # exception, the check is subdued.
    #
    # @param check [Hash] definition.
    # @return [TrueClass, FalseClass]
    def check_subdued?(check)
      if check[:subdue]
        in_time_windows?(check[:subdue])
      else
        false
      end
    end

    # Determine the next check cron time.
    #
    # @param check [Hash] definition.
    def determine_check_cron_time(check)
      cron_parser = CronParser.new(check[:cron])
      current_time = Time.now
      next_cron_time = cron_parser.next(current_time)
      next_cron_time - current_time
    end
  end
end
