require "action_controller/railtie"
require "logger"
require "sqs_web"

class RailsApp < Rails::Application
  config.logger = Rails.logger = Logger.new("test.log")
  config.secret_token = "a3d6cee7966878577a764ed273359d9e"

  routes.draw do
    match "/sqs" => SqsWeb, :anchor => false, via: [:get, :post]
  end
end
