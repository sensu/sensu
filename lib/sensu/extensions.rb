module Sensu
  class Extensions
    def initialize(settings)
      @settings = settings
      @logger = Logger.get
      @extensions = Hash.new
      EXTENSION_CATEGORIES.each do |category|
        @extensions[category] = Hash.new
      end
    end

    def [](key)
      @extensions[key]
    end

    EXTENSION_CATEGORIES.each do |category|
      define_method(category.to_s.chop + '_exists?') do |extension_name|
        @extensions[category].has_key?(extension_name)
      end
    end

    def require_directory(directory)
      Dir.glob(File.join(directory, '**/*.rb')).each do |file|
        begin
          require file
        rescue ScriptError => error
          @logger.error('failed to require extension', {
            :extension_file => file,
            :error => error
          })
          @logger.warn('ignoring extension', {
            :extension_file => file
          })
        end
      end
    end

    def load_all
      require_directory(File.join(File.dirname(__FILE__), 'extensions'))
      EXTENSION_CATEGORIES.each do |category|
        extension_type = category.to_s.chop
        Extension.const_get(extension_type.capitalize).descendants.each do |klass|
          extension = klass.new
          extension.settings = @settings
          @extensions[category][extension.name] = extension
          loaded(extension_type, extension.name, extension.description)
        end
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
      attr_accessor :settings
      
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

      def run(event=nil, &block)
        block.call('noop', 0)
      end

      def self.descendants
        ObjectSpace.each_object(Class).select do |klass|
          klass < self
        end
      end
    end

    EXTENSION_CATEGORIES.each do |category|
      extension_type = category.to_s.chop
      Object.const_set(extension_type.capitalize, Class.new(Base))
    end
  end
end
