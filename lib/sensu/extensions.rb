module Sensu
  class Extensions
    attr_reader :mutators

    def initialize
      @mutators = Hash.new
    end

    def load!
      extensions_glob = File.join(File.dirname(__FILE__), 'extensions/**/*.rb')
      Dir.glob(extensions_glob, &method(:require))
      Sensu::Extension::Mutator.descendants.each do |klass|
        mutator = klass.new
        @mutators[mutator.name] = mutator
      end
    end

    def self.get
      extensions = self.new
      extensions.load!
      extensions
    end
  end

  module Extension
    class Base
      def name
        'base'
      end

      def run(data=nil, &block)
        block.call('noop', 0)
      end

      def self.descendants
        ObjectSpace.each_object(Class).select do |klass|
          klass < self
        end
      end
    end

    class Mutator < Base; end
  end
end
