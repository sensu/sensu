module Sensu
  class Extensions
    attr_reader :mutators, :handlers

    def initialize
      @logger = Sensu::Logger.get
      @mutators = Hash.new
      @handlers = Hash.new
    end

    def mutator_exists?(mutator_name)
      @mutators.include?(mutator_name)
    end

    def handler_exists?(handler_name)
      @handlers.include?(handler_name)
    end

    def load_all
      extensions_glob = File.join(File.dirname(__FILE__), 'extensions/**/*.rb')
      Dir.glob(extensions_glob, &method(:require))
      Sensu::Extension::Mutator.descendants.each do |klass|
        mutator = klass.new
        @mutators[mutator.name] = mutator
        loaded('mutator', mutator.name, mutator.description)
      end
      Sensu::Extension::Handler.descendants.each do |klass|
        handler = klass.new
        @handlers[handler.name] = handler
        loaded('handler', handler.name, handler.description)
      end
    end

    private

    def loaded(type, name, description)
      @logger.info('loaded extension', {
        :type => type,
        :name => name,
        :description => description
      })
    end
  end

  module Extension
    class Base
      def name
        'base'
      end

      def description
        'extension description (change me)'
      end

      def definition
        {
          :type => 'extension',
          :name => name
        }
      end

      def [](key)
        definition[key.to_sym]
      end

      def has_key?(key)
        definition.has_key?(key.to_sym)
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
    class Handler < Base; end
  end
end
