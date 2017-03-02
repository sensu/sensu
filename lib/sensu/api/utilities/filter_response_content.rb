module Sensu
  module API
    module Utilities
      module FilterResponseContent
        # Create a nested hash from a dot notation key and value.
        #
        # @param dot_notation [String]
        # @param value [Object]
        # @return [Hash]
        def dot_notation_to_hash(dot_notation, value)
          hash = {}
          dot_notation.split(".").reverse.each do |key|
            if hash.empty?
              hash = {key.to_sym => value}
            else
              hash = {key.to_sym => hash}
            end
          end
          hash
        end

        # Deep merge two hashes. Nested hashes are deep merged, arrays
        # are concatenated and duplicate array items are removed.
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

        # Determine if all attribute values match those of the
        # corresponding object attributes. Attributes match if the
        # value objects are equivalent, are both hashes with matching
        # key/value pairs (recursive), or have equal string values.
        #
        # @param object [Hash]
        # @param match_attributes [Object]
        # @param object_attributes [Object]
        # @return [TrueClass, FalseClass]
        def attributes_match?(object, match_attributes, object_attributes=nil)
          object_attributes ||= object
          match_attributes.all? do |key, value_one|
            value_two = object_attributes[key]
            case
            when value_one == value_two
              true
            when value_one.is_a?(Hash) && value_two.is_a?(Hash)
              attributes_match?(object, value_one, value_two)
            when value_one.to_s == value_two.to_s
              true
            else
              false
            end
          end
        end

        # Filter the response content if filter parameters have been
        # provided. This method mutates `@response_content`.
        def filter_response_content!
          if @response_content.is_a?(Array) && !@filter_params.empty?
            attributes = {}
            @filter_params.each do |key, value|
              attributes = deep_merge(attributes, dot_notation_to_hash(key, value))
            end
            @response_content.select! do |object|
              attributes_match?(object, attributes)
            end
          end
        end
      end
    end
  end
end
