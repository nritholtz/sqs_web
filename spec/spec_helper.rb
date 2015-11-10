require "codeclimate-test-reporter"
require 'capybara/rspec'
CodeClimate::TestReporter.start

ENV['RACK_ENV'] = 'development'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include Capybara::DSL
end