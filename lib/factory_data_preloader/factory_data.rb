require 'ostruct'

module FactoryDataPreloader
  class PreloaderAlreadyDefinedError < StandardError; end
  class PreloadedRecordNotFound < StandardError; end
  class DefinedPreloaderNotRunError < StandardError; end

  module Methods
  end

  class FactoryData
    @@preloaded_cache = nil
    @@preloaded_data_deleted = nil
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

        model_class = options[:model_class] || model_type.to_s.singularize.classify.constantize
        depends_on = [options[:depends_on]].compact.flatten
        FactoryDataPreloader::Preloader.new(model_type, model_class, proc, depends_on)

        Methods.class_eval do
          define_method model_type do |key|
            FactoryData.send(:get_record, model_type, model_class, key)
          end
        end
      end

      def delete_preload_data!
        # make sure this only runs once...
        return unless @@preloaded_data_deleted.nil?

        # Delete them in the reverse order of the dependencies, to handle foreign keys
        FactoryDataPreloader.requested_preloaders.reverse.each do |preloader|
          preloader.model_class.delete_all
        end

        @@preloaded_data_deleted = true
      end

      def preload_data!
        return unless @@preloaded_cache.nil? # make sure the data is only preloaded once.
        @@preloaded_cache = {}

        FactoryDataPreloader.requested_preloaders.dependency_order.each do |preloader|
          cache = @@preloaded_cache[preloader.model_type] ||= {}
          preloader.data.each do |key, record|
            if record.new_record? && !record.save
              puts "\nError preloading factory data.  #{preloader.model_class.to_s} :#{key.to_s} could not be saved.  Errors: "
              puts pretty_error_messages(record)
              puts "\n\n"
              next
            end

            cache[key] = record.id
          end
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

      def get_record(type, model_class, key)
        if @@preloaded_cache[type].nil?
          raise DefinedPreloaderNotRunError, "The :#{type} preloader has never been run.  Did you forget to add the 'preload_factory_data :#{type}' declaration to your test case?  You'll need this at the top of your test case class if you want to use the factory data defined by this preloader."
        end

        @@single_test_cache[type] ||= {}
        @@single_test_cache[type][key] ||= begin
          record = model_class.find_by_id(@@preloaded_cache[type][key])
          raise PreloadedRecordNotFound.new, "Could not find a record for FactoryData.#{type}(:#{key})." unless record
          record
        end
      end

      # Borrowed from shoulda: http://github.com/thoughtbot/shoulda/blob/e02228d45a879ff92cb72b84f5fccc6a5f856a65/lib/shoulda/active_record/helpers.rb#L4-9
      def pretty_error_messages(obj)
        obj.errors.map do |a, m|
          msg = "#{a} #{m}"
          msg << " (#{obj.send(a).inspect})" unless a.to_sym == :base
        end
      end
    end

    self.definition_file_paths = %w(factory_data test/factory_data spec/factory_data)
  end
end

# alias this class so that apps that use it don't have to use the fully qualified name.
FactoryData = FactoryDataPreloader::FactoryData