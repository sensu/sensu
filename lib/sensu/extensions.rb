module Sensu
  class Extensions
    def initialize
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
      define_method(category) do
        @extensions[category].map do |name, extension|
          extension.definition
        end
      end

      define_method(category.to_s.chop + '_exists?') do |name|
        @extensions[category].has_key?(name)
      end
    end

    def require_directory(directory)
      path = directory.gsub(/\\(?=\S)/, '/')
      Dir.glob(File.join(path, '**/*.rb')).each do |file|
        begin
          require File.expand_path(file)
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
          @extensions[category][extension.name] = extension
          loaded(extension_type, extension.name, extension.description)
        end
      end
    end

    def stop_all(&block)
      all = @extensions.map do |category, extensions|
        extensions.map do |name, extension|
          extension
        end
      end
      all.flatten!
      stopper = Proc.new do |extension|
        if extension.nil?
          block.call
        else
          extension.stop do
            stopper.call(all.pop)
          end
        end
      end
      stopper.call(all.pop)
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

      def run(event=nil, settings={}, &block)
        block.call('noop', 0)
      end

      def stop(&block)
        block.call
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
