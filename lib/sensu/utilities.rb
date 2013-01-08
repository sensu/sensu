module Sensu
  module Utilities
    def testing?
      File.basename($0) == 'rake'
    end

    def retry_until_true(wait=0.5, &block)
      EM::Timer.new(wait) do
        unless block.call
          retry_until_true(wait, &block)
        end
      end
    end

    def hash_values_equal?(hash_one, hash_two)
      hash_one.keys.all? do |key|
        if hash_one[key] == hash_two[key]
          true
        else
          if hash_one[key].is_a?(Hash) && hash_two[key].is_a?(Hash)
            hash_values_equal?(hash_one[key], hash_two[key])
          else
            false
          end
        end
      end
    end
  end
end
