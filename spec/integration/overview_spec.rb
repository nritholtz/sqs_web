RSpec.describe "Overview Page", :sqs do
  it "will show Visible Messages" do
    default_messages

    visit "/sqs/overview"

    match_content(page, "#{SOURCE_QUEUE_NAME} 5 0 N/A")
    match_content(page, "#{DLQ_QUEUE_NAME} 3 0 #{source_queue_url}")
  end

  it "will show In Flight Messages" do
    default_messages

    receive_messages(source_queue_url, {count: 3})
    receive_messages(dlq_queue_url, {count: 2})
    
    visit "/sqs/overview"

    match_content(page, "#{SOURCE_QUEUE_NAME} 2 3 N/A")
    match_content(page, "#{DLQ_QUEUE_NAME} 1 2 #{source_queue_url}")
  end

  it "should be default page" do
    visit "/sqs"

    expect(current_path).to eq "/sqs/overview"
  end

  it "should gracefully handle non existent queues" do
    SqsWeb.options[:queues] = ["BOGUSQUEUE"]

    visit "/sqs/overview"

    match_content(page, "<Aws::SQS::Errors::NonExistentQueue: BOGUSQUEUE is not an existing queue name>: BOGUSQUEUE is not an existing queue name")
  end
end