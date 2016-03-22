require "securerandom"

module Sensu
  module Utilities
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
          hash_one[key].concat(value).uniq
        else
          value
        end
      end
      merged
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
    # @param hash [Hash] to redact sensitive value from.
    # @param keys [Array] that indicate sensitive values.
    # @return [Hash] hash with redacted sensitive values.
    def redact_sensitive(hash, keys=nil)
      keys ||= %w[
        password passwd pass
        api_key api_token
        access_key secret_key private_key
        secret
      ]
      hash = hash.dup
      hash.each do |key, value|
        if keys.include?(key.to_s)
          hash[key] = "REDACTED"
        elsif value.is_a?(Hash)
          hash[key] = redact_sensitive(value, keys)
        elsif value.is_a?(Array)
          hash[key] = value.map do |item|
            item.is_a?(Hash) ? redact_sensitive(item, keys) : item
          end
        end
      end
      hash
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
      substituted = tokens.gsub(/:::([^:].*?):::/) do
        token, default = $1.to_s.split("|", -1)
        matched = find_attribute_value(attributes, token.split("."), default)
        if matched.nil?
          unmatched_tokens << token
        end
        matched
      end
      [substituted, unmatched_tokens]
    end
  end
end
