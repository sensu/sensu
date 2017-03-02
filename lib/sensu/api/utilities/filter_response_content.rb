require "sensu/utilities"

module Sensu
  module API
    module Utilities
      module FilterResponseContent
        include Sensu::Utilities

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

        # Filter the response content if filter parameters have been
        # provided. This method mutates `@response_content`, only
        # retaining array items that match the attributes provided via
        # filter parameters.
        def filter_response_content!
          if @response_content.is_a?(Array) && !@filter_params.empty?
            attributes = {}
            @filter_params.each do |key, value|
              attributes = deep_merge(attributes, dot_notation_to_hash(key, value))
            end
            @response_content.select! do |object|
              attributes_match?(object, attributes, false)
            end
          end
        end
      end
    end
  end
end
