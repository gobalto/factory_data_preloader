require 'rubygems'
require 'test/unit'
require 'shoulda'

begin
  require 'ruby-debug'
  Debugger.start
  Debugger.settings[:autoeval] = true if Debugger.respond_to?(:settings)
rescue LoadError
  # ruby-debug wasn't available so neither can the debugging be
end


$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'factory_data_preloader'

ActiveRecord::Base.establish_connection({ :database => ":memory:", :adapter => 'sqlite3', :timeout => 500 })

module OutputCapturer
  # borrowed from zentest assertions...
  def self.capture
    require 'stringio'
    orig_stdout = $stdout.dup
    orig_stderr = $stderr.dup
    captured_stdout = StringIO.new
    captured_stderr = StringIO.new
    $stdout = captured_stdout
    $stderr = captured_stderr
    yield
    captured_stdout.rewind
    captured_stderr.rewind
    return captured_stdout.string, captured_stderr.string
  ensure
    $stdout = orig_stdout
    $stderr = orig_stderr
  end
end

module FactoryDataPreloader
  def self.reset!
    self.preload_all = true
    self.preload_types = []
    @requested_preloaders = nil
    FactoryData.reset!
  end

  class FactoryData
    # helper method to reset the factory data between test runs.
    def self.reset!
      FactoryDataPreloader::AllPreloaders.instance.each do |preloader|
        Methods.class_eval do
          remove_method(preloader.model_type) if method_defined?(preloader.model_type)
        end

        if preloader.data
          preloader.model_class.delete_all(:id => preloader.data.record_ids)
          preloader.instance_variable_set('@data', nil)
        end
      end

      @@single_test_cache = {}
      FactoryDataPreloader::AllPreloaders.instance.clear
    end
  end
end

require 'lib/schema'
require 'lib/models'