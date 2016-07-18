require "codeclimate-test-reporter"
require "byebug"
require 'capybara/rspec'
require 'support/shared_context.rb'
CodeClimate::TestReporter.start

ENV['RACK_ENV'] = 'development'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include Capybara::DSL
end

Capybara.javascript_driver = :selenium

def match_content(actual, expected)
  actual_text = actual.respond_to?(:text) ? normalize_whitespace(actual.text) : actual
  expect(actual_text).to include(expected), <<-EOF
  expected
  "#{actual_text}"
  to have content
  "#{expected}"
  EOF
end

def normalize_whitespace(content)
  Capybara::Helpers.normalize_whitespace(content)
end