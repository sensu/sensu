gem 'uuidtools', '2.1.4'

require 'uuidtools'

module Sensu
  module Utilities
    def testing?
      File.basename($0) == 'rspec'
    end

    def retry_until_true(wait=0.5, &block)
      EM::Timer.new(wait) do
        unless block.call
          retry_until_true(wait, &block)
        end
      end
    end

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

    def random_uuid
      UUIDTools::UUID.random_create.to_s
    end

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
  end
end
