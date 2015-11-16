require 'sqs_web/application/flash_message'
require 'sqs_web/application/navigation'
require 'sqs_web/application/app'
require 'sqs_web/application/aws_action'
require 'sqs_web/application/exception_handle'
require 'sqs_web/railtie' if defined?(Rails)
AwsAction.initialize_aws
