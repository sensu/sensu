module Sensu
  class Extensions
    attr_reader :mutators

    def initialize
      @mutators = Hash.new
    end

    def load!
      Dir.glob('sensu/extensions/*.rb', &method(:require))
      Sensu::Extension::Mutator.descendents.each do |klass|
        mutator = klass.new
        @mutators[mutator.name] = mutator
      end
    end
  end

  module Extension
    class Base
      attr_reader :type, :name

      def initialize
        @type = 'base'
        @name = 'base'
      end

      def run(data=nil)
        ['noop', 0]
      end

      def self.descendants
        ObjectSpace.each_object(Class).select do |klass|
          klass < self
        end
      end
    end

    class Mutator < Base
      def initialize
        super
        @type = :mutator
      end
    end
  end
end
