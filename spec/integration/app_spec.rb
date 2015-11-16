require 'support/rails_app'
require 'support/fake_sqs'

Capybara.app = RailsApp

RSpec.describe "Mounted in Rails Application", :sqs do

  SOURCE_QUEUE_NAME = "TestSourceQueue"

  DLQ_QUEUE_NAME = "TestSourceQueueDLQ"

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

  # basic smoke test all the tabs
  %w(overview dlq_console).each do |tab|
    specify "test_#{tab}" do
      visit "/sqs/#{tab}"
      expect(page.status_code).to eq 200
    end
  end

  describe "Overview page" do
    it "will show Visible Messages" do
      default_messages

      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 5 0 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 3 0 #{source_queue_url}")
    end

    specify "In Flight Messages" do
      default_messages

      receive_messages(source_queue_url, 3)
      receive_messages(dlq_queue_url, 2)
      
      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 2 3 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 1 2 #{source_queue_url}")
    end

    specify "should be default page" do
      visit "/sqs"

      expect(current_path).to eq "/sqs/overview"
    end

    specify "handle non existent queues" do
      SqsWeb.options[:queues] = ["BOGUSQUEUE"]

      visit "/sqs/overview"

      match_content(page, "Aws::SQS::Errors::NonExistentQueue: BOGUSQUEUE")
    end
  end

  describe "DLQ Console" do
    it "should delete single message" do
      messages = generate_messages(dlq_queue_url, 2)
      deleted_message_id = messages.pop.message_id
      retained_message_id = messages.pop.message_id

      visit "/sqs/dlq_console"

      within("##{deleted_message_id}") do
        click_on "Remove"
      end

      success_message = "Message ID: #{deleted_message_id} in Queue #{DLQ_QUEUE_NAME} was successfully removed."
      expect(first("#alert").text).to eq success_message

      expect(page.all("##{deleted_message_id}").count).to eq 0
      expect(page.all("##{retained_message_id}").count).to eq 1

      visit "/sqs/overview"

      match_content(page, "#{DLQ_QUEUE_NAME} 1 0 #{source_queue_url}")
    end

    it "should only show unique entries for each message" do
      message_ids = generate_messages(dlq_queue_url, 5).map{|c| c.message_id}

      visit "/sqs/dlq_console"

      message_ids.each{|message_id| expect(page.all("##{message_id}").count).to eq 1}
    end

    it "should handle deleting single message that is already deleted" do
      deleted_message_id = generate_messages(dlq_queue_url, 1).first.message_id
      
      visit "/sqs/dlq_console"

      sqs.purge_queue({ queue_url: dlq_queue_url })

      within("##{deleted_message_id}") do
        click_on "Remove"
      end
      
      error_message = "Message ID: #{deleted_message_id} in Queue #{DLQ_QUEUE_NAME} has already been deleted or is not visible."
      expect(first("#alert").text).to eq error_message
    end

    it "should render all information related to the visible messages" do
      generate_messages(dlq_queue_url, 1)

      visit "/sqs/dlq_console"

      message = receive_messages(dlq_queue_url).messages.first
      message.attributes["ApproximateReceiveCount"] = "1"

      message_metadata = <<-EOF
      ID #{message.message_id} or Receive Count 1 
      Queue Name #{DLQ_QUEUE_NAME} Origin Queue #{source_queue_url}
      Message Body Test_0
      EOF

      message_entry = first("##{message.message_id}")
      match_content(message_entry, normalize_whitespace(message_metadata))
      match_content(message_entry, normalize_whitespace(message.inspect.to_yaml.split('receipt_handle')[0]))
      match_content(message_entry, normalize_whitespace(message.inspect.to_yaml.split('md5', 2)[1]))
      match_content(message_entry, normalize_whitespace("Enqueued At #{Time.at(message.attributes["SentTimestamp"].to_i/1000).rfc822}"))
    end

    it "should not display any messages that are not in a DLQ" do
      generate_messages(source_queue_url, 1)

      visit "/sqs/dlq_console"

      message = receive_messages(source_queue_url).messages.first

      expect(first("##{message.message_id}")).to be_nil

      match_content(page, "Showing 0 visible messages")
    end

    it "should be able to move a single message to source queue" do
      message_id = generate_messages(dlq_queue_url, 1).first.message_id
      
            
      visit "/sqs/dlq_console"

      within("##{message_id}") do
        click_on "Move to Source Queue"
      end

      success_message = "Message ID: #{message_id} in Queue #{DLQ_QUEUE_NAME} was successfully moved to Source Queue #{source_queue_url}."
      expect(first("#alert").text).to eq success_message
      expect(page.all("##{message_id}").count).to eq 0

      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 1 0 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 0 0 #{source_queue_url}")

      moved_message = receive_messages(source_queue_url).messages.first
      expect(moved_message).to_not be_nil
      expect(moved_message.body).to eq "Test_0"
      expect(moved_message.attributes["ApproximateReceiveCount"]).to eq "1"
      expect(moved_message.message_attributes["foo_class"].to_hash).to eq({string_value: "FooWorker", data_type: "String"})
    end
  end

  def receive_messages(queue_url, count=1)
    sqs.receive_message({
      queue_url: queue_url,
      attribute_names: ["All"],
      message_attribute_names: ["All"],
      max_number_of_messages: count,
      wait_time_seconds: 1
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
