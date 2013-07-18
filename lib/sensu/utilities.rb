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

    def indifferent_hash
      Hash.new do |hash, key|
        if key.is_a?(String)
          hash[key.to_sym]
        end
      end
    end

    def with_indifferent_access(hash)
      hash = indifferent_hash.merge(hash)
      hash.each do |key, value|
        if value.is_a?(Hash)
          hash[key] = with_indifferent_access(value)
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

    def deep_diff(hash_one, hash_two)
      keys = hash_one.keys.concat(hash_two.keys).uniq
      keys.inject(Hash.new) do |diff, key|
        unless hash_one[key] == hash_two[key]
          if hash_one[key].is_a?(Hash) && hash_two[key].is_a?(Hash)
            diff[key] = deep_diff(hash_one[key], hash_two[key])
          else
            diff[key] = [hash_one[key], hash_two[key]]
          end
        end
        diff
      end
    end

    def redact_passwords(hash)
      hash = hash.dup
      hash.each do |key, value|
        if %w[password passwd pass].include?(key.to_s)
          hash[key] = "REDACTED"
        elsif value.is_a?(Hash)
          hash[key] = redact_passwords(value)
        end
      end
      hash
    end
  end
end
