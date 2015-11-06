require 'support/rails_app'
require 'support/fake_sqs'

RSpec.describe "Mounted in Rails Application", :sqs do
  include Rack::Test::Methods
  def app
    RailsApp
  end

  QUEUE_NAME = "test-source"

  let(:sqs) { Aws::SQS::Client.new(region: "us-east-1", credentials: Aws::Credentials.new("fake", "fake")) }

  let(:queue_url) { sqs.get_queue_url(queue_name: QUEUE_NAME).queue_url }

  before do
    sqs.config.endpoint = $fake_sqs.uri
    sqs.create_queue(queue_name: QUEUE_NAME)
    SqsWeb.options[:queues] = [QUEUE_NAME]
  end

  # basic smoke test all the tabs
  %w(overview dlq_console).each do |tab|
    specify "test_#{tab}" do
      get "/sqs/#{tab}"
      expect(last_response).to be_ok
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

end
