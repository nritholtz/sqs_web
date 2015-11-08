## Configure your application with the following settings
# SqsWeb.options[:aws][:endpoint] = "http://localhost:4568"
# SqsWeb.options[:queues] =  ["TestSourceQueue", "TestSourceQueueDLQ"]
# SqsWeb.options[:aws][:access_key_id] = "fake"
# SqsWeb.options[:aws][:secret_access_key] = "fake"

require "fake_sqs/test_integration"
require 'aws-sdk'

def generate_messages(sqs_client, queue_url)
  (Random.rand(7)+1).times do |time|
    puts "Creating message Test_#{time} in queue URL #{queue_url}"
    sqs_client.send_message(queue_url: queue_url, message_body: "Test_#{time}")
  end
end

$fake_sqs = FakeSQS::TestIntegration.new(
  database: ":memory:",
  sqs_endpoint: "localhost",
  sqs_port: 4568,
)
$fake_sqs.start
sqs = Aws::SQS::Client.new(endpoint: $fake_sqs.uri, region: 'us-east-1', credentials: Aws::Credentials.new("fake", "fake"))
# Create queues
source_queue_url = sqs.create_queue(queue_name: "TestSourceQueue").queue_url
dlq_queue_url = sqs.create_queue(queue_name: "TestSourceQueueDLQ").queue_url

#Set DLQ
dlq_arn = sqs.get_queue_attributes(queue_url: dlq_queue_url).attributes.fetch("QueueArn")
sqs.set_queue_attributes(
  queue_url: source_queue_url, 
  attributes: {
    "RedrivePolicy" => "{\"deadLetterTargetArn\":\"#{dlq_arn}\",\"maxReceiveCount\":10}"
  }
)

#Generate messages
[source_queue_url, dlq_queue_url].each{|queue| generate_messages(sqs, queue)}

puts "Press enter to shutdown"
gets
$fake_sqs.stop

