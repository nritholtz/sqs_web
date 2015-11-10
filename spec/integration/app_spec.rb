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

      expect(page).to have_content "#{SOURCE_QUEUE_NAME} 5 0 N/A" 
      expect(page).to have_content "#{DLQ_QUEUE_NAME} 3 0 #{source_queue_url}"
    end

    specify "In Flight Messages" do
      default_messages

      receive_messages(source_queue_url, 3)
      receive_messages(dlq_queue_url, 2)
      
      visit "/sqs/overview"

      expect(page).to have_content "#{SOURCE_QUEUE_NAME} 2 3 N/A" 
      expect(page).to have_content "#{DLQ_QUEUE_NAME} 1 2 #{source_queue_url}"
    end

    specify "should be default page" do
      visit "/sqs"

      expect(current_path).to eq "/sqs/overview"
    end

    specify "handle non existent queues" do
      SqsWeb.options[:queues] = ["BOGUSQUEUE"]

      visit "/sqs/overview"

      expect(page).to have_content "Aws::SQS::Errors::NonExistentQueue: BOGUSQUEUE"
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

      expect(page).to have_content "#{DLQ_QUEUE_NAME} 1 0 #{source_queue_url}"
    end

    it "should only show unique entries for each message" do
      message_ids = generate_messages(dlq_queue_url, 5).map{|c| c.message_id}

      visit "/sqs/dlq_console"

      message_ids.each{|message_id| expect(page.all("##{message_id}").count).to eq 1}
    end
  end
  # specify "SendMessage" do
  #   msg = "this is my message"

  #   result = sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: msg,
  #   )

  #   expect(result.md5_of_message_body).to eq Digest::MD5.hexdigest(msg)
  #   expect(result.message_id.size).to eq 36
  # end

  # specify "ReceiveMessage" do
  #   body = "test 123"

  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: body
  #   )

  #   response = sqs.receive_message(
  #     queue_url: queue_url,
  #   )

  #   expect(response.messages.size).to eq 1

  #   expect(response.messages.first.body).to eq body
  # end

  # specify "DeleteMessage" do
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: "test",
  #   )

  #   message1 = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first

  #   sqs.delete_message(
  #     queue_url: queue_url,
  #     receipt_handle: message1.receipt_handle,
  #   )

  #   let_messages_in_flight_expire

  #   response = sqs.receive_message(
  #     queue_url: queue_url,
  #   )
  #   expect(response.messages.size).to eq 0
  # end

  # specify "DeleteMessageBatch" do
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: "test1"
  #   )
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: "test2"
  #   )

  #   messages_response = sqs.receive_message(
  #     queue_url: queue_url,
  #     max_number_of_messages: 2,
  #   )

  #   entries = messages_response.messages.map { |msg|
  #     {
  #       id: SecureRandom.uuid,
  #       receipt_handle: msg.receipt_handle,
  #     }
  #   }

  #   sqs.delete_message_batch(
  #     queue_url: queue_url,
  #     entries: entries,
  #   )

  #   let_messages_in_flight_expire

  #   response = sqs.receive_message(
  #     queue_url: queue_url,
  #   )
  #   expect(response.messages.size).to eq 0
  # end

  # specify "PurgeQueue" do
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: "test1"
  #   )
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: "test2"
  #   )

  #   sqs.purge_queue(
  #     queue_url: queue_url,
  #   )

  #   response = sqs.receive_message(
  #     queue_url: queue_url,
  #   )
  #   expect(response.messages.size).to eq 0
  # end

  # specify "SendMessageBatch" do
  #   bodies = %w(a b c)

  #   sqs.send_message_batch(
  #     queue_url: queue_url,
  #     entries: bodies.map { |bd|
  #       {
  #         id: SecureRandom.uuid,
  #         message_body: bd,
  #       }
  #     }
  #   )

  #   messages_response = sqs.receive_message(
  #     queue_url: queue_url,
  #     max_number_of_messages: 3,
  #   )

  #   expect(messages_response.messages.map(&:body)).to match_array bodies
  # end

  # specify "set message timeout to 0" do
  #   body = 'some-sample-message'

  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: body,
  #   )

  #   message = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first

  #   expect(message.body).to eq body

  #   sqs.change_message_visibility(
  #     queue_url: queue_url,
  #     receipt_handle: message.receipt_handle,
  #     visibility_timeout: 0
  #   )

  #   same_message = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first
  #   expect(same_message.body).to eq body
  # end

  # specify 'set message timeout and wait for message to come' do

  #   body = 'some-sample-message'

  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: body,
  #   )

  #   message = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first
  #   expect(message.body).to eq body

  #   sqs.change_message_visibility(
  #     queue_url: queue_url,
  #     receipt_handle: message.receipt_handle,
  #     visibility_timeout: 2
  #   )

  #   nothing = sqs.receive_message(
  #     queue_url: queue_url,
  #   )
  #   expect(nothing.messages.size).to eq 0

  #   sleep(5)

  #   same_message = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first
  #   expect(same_message.body).to eq body
  # end

  # specify 'should fail if trying to update the visibility_timeout for a message that is not in flight' do
  #   body = 'some-sample-message'
  #   sqs.send_message(
  #     queue_url: queue_url,
  #     message_body: body,
  #   )

  #   message = sqs.receive_message(
  #     queue_url: queue_url,
  #   ).messages.first
  #   expect(message.body).to eq body

  #   sqs.change_message_visibility(
  #     queue_url: queue_url,
  #     receipt_handle: message.receipt_handle,
  #     visibility_timeout: 0
  #   )

  #   expect {
  #     sqs.change_message_visibility(
  #       queue_url: queue_url,
  #       receipt_handle: message.receipt_handle,
  #       visibility_timeout: 30
  #     )
  #   }.to raise_error(Aws::SQS::Errors::MessageNotInflight)
  # end

  # def let_messages_in_flight_expire
  #   $fake_sqs.expire
  # end

  def receive_messages(queue_url, count=1)
    sqs.receive_message({
      queue_url: queue_url,
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
      messages << sqs.send_message(queue_url: queue_url, message_body: "Test_#{time}")
    end
    messages
  end
end
