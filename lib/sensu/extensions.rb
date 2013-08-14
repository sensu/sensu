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

    def load_settings(settings={})
      all_extensions.each do |extension|
        extension.settings = settings
      end
    end

    def stop_all(&block)
      extensions = all_extensions
      stopper = Proc.new do |extension|
        if extension.nil?
          block.call
        else
          extension.stop do
            stopper.call(extensions.pop)
          end
        end
      end
      stopper.call(extensions.pop)
    end

    private

    def all_extensions
      all = @extensions.map do |category, extensions|
        extensions.map do |name, extension|
          extension
        end
      end
      all.flatten!
    end

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

      def initialize
        EM::next_tick do
          post_init
        end
      end

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

      def post_init
        true
      end

      def run(data=nil, &block)
        block.call('noop', 0)
      end

      def stop(&block)
        block.call
      end

      def [](key)
        definition[key.to_sym]
      end

      def has_key?(key)
        definition.has_key?(key.to_sym)
      end

      def safe_run(data=nil, &block)
        begin
          data ? run(data.dup, &block) : run(&block)
        rescue => error
          block.call(error.to_s, 2)
        end
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
