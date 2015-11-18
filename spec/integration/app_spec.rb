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

      receive_messages(source_queue_url, {count: 3})
      receive_messages(dlq_queue_url, {count: 2})
      
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

  describe "DLQ Console", js: true do

    it "should only show unique entries for each message" do
      message_ids = generate_messages(dlq_queue_url, 5).map{|c| c.message_id}

      visit "/sqs/dlq_console"

      message_ids.each{|message_id| expect(page.all("#message_#{message_id}").count).to eq 1}
    end

    it "should delete single message" do
      messages = generate_messages(dlq_queue_url, 2)
      deleted_message_id = messages.pop.message_id
      retained_message_id = messages.pop.message_id

      visit "/sqs/dlq_console"

      first("#message_#{deleted_message_id}").hover

      within("#message_#{deleted_message_id}") do
        click_on "Remove"
      end

      success_message = "Message ID: #{deleted_message_id} in Queue #{DLQ_QUEUE_NAME} was successfully removed."
      expect(first("#alert").text).to eq success_message

      expect(page.all("#message_#{deleted_message_id}").count).to eq 0
      expect(page.all("#message_#{retained_message_id}").count).to eq 1

      visit "/sqs/overview"

      match_content(page, "#{DLQ_QUEUE_NAME} 1 0 #{source_queue_url}")
    end

    it "should handle deleting single message that is already deleted" do
      deleted_message_id = generate_messages(dlq_queue_url, 1).first.message_id
      
      visit "/sqs/dlq_console"

      sqs.purge_queue({ queue_url: dlq_queue_url })

      first("#message_#{deleted_message_id}").hover

      within("#message_#{deleted_message_id}") do
        click_on "Remove"
      end
      
      error_message = "Message ID: #{deleted_message_id} in Queue #{DLQ_QUEUE_NAME} has already been deleted or is not visible."
      expect(first("#alert").text).to eq error_message
    end

    it "should remove multiple selected messages" do
      messages = generate_messages(dlq_queue_url, 6)
      deleted_message_ids = messages.pop(4).map{|c| c.message_id}
      retained_message_ids = messages.pop(2).map{|c| c.message_id}

      visit "/sqs/dlq_console"

      deleted_message_ids.each do |message_id|
        first("#batch_action_item_#{message_id}").set(true)
      end
      
      click_on "Bulk Remove"

      expect(first("#alert").text).to eq "Selected messages have been removed successfully."

      deleted_message_ids.each{|message_id| expect(page.all("#message_#{message_id}").count).to eq 0}
      retained_message_ids.each{|message_id| expect(page.all("#message_#{message_id}").count).to eq 1}

      visit "/sqs/overview"

      match_content(page, "#{DLQ_QUEUE_NAME} 2 0 #{source_queue_url}")
    end

    it "should handle removing multiple selected messages where one or more is already deleted or not visible" do
      generate_messages(dlq_queue_url, 3)
      
      visit "/sqs/dlq_console"
      
      messages = receive_messages(dlq_queue_url, {count: 3}).messages
      sqs.delete_message({queue_url: dlq_queue_url, receipt_handle: messages[2].receipt_handle})
      sqs.change_message_visibility_batch({
        queue_url: dlq_queue_url,
        entries: messages.take(2).map do |message| 
          {id: message.message_id, receipt_handle: message.receipt_handle, visibility_timeout: 0}
        end
      })
      messages.each do |message|
        first("#batch_action_item_#{message.message_id}").set(true)
      end
      
      click_on "Bulk Remove"

      expect(first("#alert").text).to eq "One or more messages may have already been removed or is not visible."

      messages.each{|message| expect(page.all("#message_#{message.message_id}").count).to eq 0}

      visit "/sqs/overview"

      match_content(page, "#{DLQ_QUEUE_NAME} 0 0 #{source_queue_url}")
    end

    it "should handle clicking on Bulk Remove without any selection" do
      messages = generate_messages(dlq_queue_url, 3)
      
      visit "/sqs/dlq_console"

      click_on "Bulk Remove"

      expect(first("#alert").text).to eq ""

      messages.each{|message| expect(page.all("#message_#{message.message_id}").count).to eq 1}
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

      message_entry = first("#message_#{message.message_id}")
      
      within(message_entry) do 
        click_on "Toggle full message"
        first(".toggle_format").click
      end
      
      match_content(message_entry, normalize_whitespace(message_metadata))
      match_content(message_entry, normalize_whitespace(message.inspect.to_yaml.split('receipt_handle')[0]))
      match_content(message_entry, normalize_whitespace(message.inspect.to_yaml.split('md5', 2)[1]))
      match_content(message_entry, normalize_whitespace("Enqueued At #{Time.at(message.attributes["SentTimestamp"].to_i/1000).rfc822}"))
    end

    it "should not display any messages that are not in a DLQ" do
      generate_messages(source_queue_url, 1)

      visit "/sqs/dlq_console"

      message = receive_messages(source_queue_url).messages.first

      expect(first("#message_#{message.message_id}")).to be_nil

      match_content(page, "Showing 0 visible messages")
    end

    it "should be able to move a single message to source queue" do
      message_id = generate_messages(dlq_queue_url, 1).first.message_id
      
            
      visit "/sqs/dlq_console"

      first("#message_#{message_id}").hover

      within("#message_#{message_id}") do
        click_on "Move to Source Queue"
      end

      success_message = "Message ID: #{message_id} in Queue #{DLQ_QUEUE_NAME} was successfully moved to Source Queue #{source_queue_url}."
      expect(first("#alert").text).to eq success_message
      expect(page.all("#message_#{message_id}").count).to eq 0

      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 1 0 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 0 0 #{source_queue_url}")

      moved_message = receive_messages(source_queue_url).messages.first
      expect(moved_message).to_not be_nil
      expect(moved_message.body).to eq "Test_0"
      expect(moved_message.attributes["ApproximateReceiveCount"]).to eq "1"
      expect(moved_message.message_attributes["foo_class"].to_hash).to eq({string_value: "FooWorker", data_type: "String"})
    end

    it "should move multiple selected messages" do
      messages = generate_messages(dlq_queue_url, 6)
      retained_message_ids = messages.pop(2).map{|c| c.message_id}
      moved_message_ids = messages.pop(4).map{|c| c.message_id}

      visit "/sqs/dlq_console"

      moved_message_ids.each do |message_id|
        first("#batch_action_item_#{message_id}").set(true)
      end
      
      click_on "Bulk Move to Source Queue"

      expect(first("#alert").text).to eq "Selected messages have been requeued successfully."

      moved_message_ids.each{|message_id| expect(page.all("#message_#{message_id}").count).to eq 0}
      retained_message_ids.each{|message_id| expect(page.all("#message_#{message_id}").count).to eq 1}

      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 4 0 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 2 0 #{source_queue_url}")

      moved_messages = receive_messages(source_queue_url, {count: 4}).messages.sort_by{|c| c.body}
      moved_messages.each_with_index do |moved_message, index|
        expect(moved_message).to_not be_nil
        expect(moved_message.body).to match "Test_#{index}"
        expect(moved_message.attributes["ApproximateReceiveCount"]).to eq "1"
        expect(moved_message.message_attributes["foo_class"].to_hash).to eq({string_value: "FooWorker", data_type: "String"})
      end
    end

    it "should handle moving multiple selected messages where one or more is already deleted or not visible" do
      generate_messages(dlq_queue_url, 3)
      
      visit "/sqs/dlq_console"
      
      messages = receive_messages(dlq_queue_url, {count: 3}).messages
      sqs.delete_message({queue_url: dlq_queue_url, receipt_handle: messages[2].receipt_handle})
      sqs.change_message_visibility_batch({
        queue_url: dlq_queue_url,
        entries: messages.take(2).map do |message| 
          {id: message.message_id, receipt_handle: message.receipt_handle, visibility_timeout: 0}
        end
      })
      messages.each do |message|
        first("#batch_action_item_#{message.message_id}").set(true)
      end
      
      click_on "Bulk Move to Source Queue"

      expect(first("#alert").text).to eq "One or more messages may have already been requeued or is not visible."

      messages.each{|message| expect(page.all("#message_#{message.message_id}").count).to eq 0}

      visit "/sqs/overview"

      match_content(page, "#{SOURCE_QUEUE_NAME} 2 0 N/A")
      match_content(page, "#{DLQ_QUEUE_NAME} 0 0 #{source_queue_url}")
    end

    it "should handle clicking on Bulk Move to Source Queue without any selection" do
      messages = generate_messages(dlq_queue_url, 3)
      
      visit "/sqs/dlq_console"

      click_on "Bulk Move to Source Queue"

      expect(first("#alert").text).to eq ""

      messages.each{|message| expect(page.all("#message_#{message.message_id}").count).to eq 1}
    end

    it "should have a select/unselect all function" do
      messages = generate_messages(dlq_queue_url, 3)
      
      visit "/sqs/dlq_console"

      first("#select_all").click

      page.all(".bulk_check").each{|node| expect(node["checked"]).to eq true}

      first("#select_all").click

      page.all(".bulk_check").each{|node| expect(node["checked"]).to eq false}
    end
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
