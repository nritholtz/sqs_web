require "fake_sqs/test_integration"

db = ENV["SQS_DATABASE"] || ":memory:"
puts "\n\e[34mRunning specs with database \e[33m#{db}\e[0m"
$fake_sqs = FakeSQS::TestIntegration.new(
  database: db,
  sqs_endpoint: "localhost",
  sqs_port: 4568,
)

SqsWeb.options[:aws][:access_key_id] = "fake"
SqsWeb.options[:aws][:secret_access_key] = "fake"
SqsWeb.options[:aws][:endpoint] = $fake_sqs.uri

RSpec.configure do |config|
  config.before(:suite) { $fake_sqs.start }
  config.before(:each, :sqs) { $fake_sqs.reset }
  config.after(:suite) { $fake_sqs.stop }
end
