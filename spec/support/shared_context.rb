SOURCE_QUEUE_NAME = "TestSourceQueue"

DLQ_QUEUE_NAME = "TestSourceQueueDLQ"

RSpec.shared_context "sqs_setup", :sqs do
  require 'support/rails_app'
  require 'support/fake_sqs'

  Capybara.app = RailsApp

  Aws::SQS::Client.remove_plugin(Aws::Plugins::SQSMd5s)

  let(:sqs) { Aws::SQS::Client.new(region: "us-east-1", credentials: Aws::Credentials.new("fake", "fake")) }

  let(:source_queue_url) { sqs.get_queue_url(queue_name: SOURCE_QUEUE_NAME).queue_url }

  let(:dlq_queue_url) { sqs.get_queue_url(queue_name: DLQ_QUEUE_NAME).queue_url }

  before do
    sqs.config.endpoint = $fake_sqs.uri
    [SOURCE_QUEUE_NAME, DLQ_QUEUE_NAME].each{|queue_name| sqs.create_queue(queue_name: queue_name)}
    dlq_arn = sqs.get_queue_attributes(queue_url: dlq_queue_url).attributes.fetch("QueueArn")
    #Set DLQ
    sqs.set_queue_attributes(
      queue_url: source_queue_url, 
      attributes: {
        "RedrivePolicy" => "{\"deadLetterTargetArn\":\"#{dlq_arn}\",\"maxReceiveCount\":10}"
      }
    )
    SqsWeb.options[:queues] = [SOURCE_QUEUE_NAME, DLQ_QUEUE_NAME]
  end

  def receive_messages(queue_url, options = {count: 1})
    sqs.receive_message({
      queue_url: queue_url,
      attribute_names: ["All"],
      message_attribute_names: ["All"],
      max_number_of_messages: options[:count],
      wait_time_seconds: 1,
      visibility_timeout: options[:visibility_timeout]
    })
  end

  def default_messages
    generate_messages(source_queue_url, 5) + generate_messages(dlq_queue_url, 3)
  end

  def generate_messages(queue_url, count=1)
    messages = []
    count.times do |time|
      messages << sqs.send_message(queue_url: queue_url, message_body: "Test_#{time}", 
        message_attributes: {"foo_class"=> {string_value: "FooWorker", data_type: "String"}})
    end
    messages
  end
end