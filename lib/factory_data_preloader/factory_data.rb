require 'ostruct'

module FactoryDataPreloader
  class PreloaderAlreadyDefinedError < StandardError; end
  class PreloadedRecordNotFound < StandardError; end
  class DefinedPreloaderNotRunError < StandardError; end
  class ErrorWhilePreloadingRecord < StandardError; end

  module Methods
  end

  class FactoryData
    @@single_test_cache = {}

    extend Methods

    class << self
      # An Array of strings specifying locations that should be searched for
      # factory_data definitions. By default, factory_data_preloader will attempt to require
      # "factory_data," "test/factory_data," and "spec/factory_data." Only the first
      # existing file will be loaded.
      attr_accessor :definition_file_paths

      def preload(model_type, options = {}, &proc)
        raise PreloaderAlreadyDefinedError.new, "You have already defined the preloader for #{model_type.to_s}" if AllPreloaders.instance.map(&:model_type).include?(model_type)

        # TODO: fix this...
        model_class = options[:model_class] || model_type.to_s.singularize.classify.constantize
        depends_on = [options[:depends_on]].compact.flatten
        FactoryDataPreloader::Preloader.new(model_type, model_class, proc, depends_on)

        Methods.class_eval do
          define_method model_type do |key|
            FactoryData.send(:get_record, model_type, key)
          end
        end
      end

      def delete_preload_data!
        # Delete them in the reverse order of the dependencies, to handle foreign keys
        FactoryDataPreloader.requested_preloaders.dependency_order.reverse.each do |preloader|
          preloader.model_class.delete_all
        end
      end

      def preload_data!
        FactoryDataPreloader.requested_preloaders.dependency_order.each do |preloader|
          preloader.preload!
        end
      end

      def reset_cache!
        @@single_test_cache = {}
      end

      def find_definitions
        definition_file_paths.each do |path|
          require("#{path}.rb") if File.exists?("#{path}.rb")

          if File.directory? path
            Dir[File.join(path, '*.rb')].each do |file|
              require file
            end
          end
        end
      end

      private

      def get_record(type, key)
        preloader = AllPreloaders.instance.from_symbol(type)
        @@single_test_cache[type]      ||= {}
        @@single_test_cache[type][key] ||= preloader.get_record(key)
      end
    end

    self.definition_file_paths = %w(factory_data test/factory_data spec/factory_data)
  end
end

# alias this class so that apps that use it don't have to use the fully qualified name.
FactoryData = FactoryDataPreloader::FactoryData