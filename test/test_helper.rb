if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails"
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # Coverage needs a single process to produce one coherent report.
    parallelize(workers: ENV["COVERAGE"] ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup { Prosopite.scan }
    teardown { Prosopite.finish }

    # Add more helper methods to be used by all tests here...
  end
end
