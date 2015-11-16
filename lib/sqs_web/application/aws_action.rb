class AwsAction
  
  protected
  
  def self.sqs
    @@sqs ||= Aws::SQS::Client.new
  end

  def self.initialize_aws
    # aws-sdk tries to load the credentials from the ENV variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
    # when not explicit supplied
    return if SqsWeb.options[:aws].empty?

    aws_options = SqsWeb.options[:aws]

    # assume credentials based authentication
    credentials = Aws::Credentials.new(
      aws_options[:access_key_id],
      aws_options[:secret_access_key])

    # but only if the configuration options have valid values
    aws_options = aws_options.merge(credentials: credentials) if credentials.set?

    Aws.config = aws_options
  end

  def self.load_queue_urls
    sqs && SqsWeb.options[:queues].map do |queue_name|
      dlq_queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
      source_queue_url = sqs.list_dead_letter_source_queues({queue_url: dlq_queue_url}).queue_urls.first
      {name:  queue_name, url: dlq_queue_url, source_url: source_queue_url}
    end
  end

  def self.get_queue_stats(queues)
    queues.each_with_object({}) do |queue, stats_summary|
      visible = in_flight = 0
      response = sqs.get_queue_attributes(queue_url: queue[:url], attribute_names: ["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"]).attributes
      visible += response["ApproximateNumberOfMessages"].to_i
      in_flight += response["ApproximateNumberOfMessagesNotVisible"].to_i
      stats_summary[queue[:name]] = {visible: visible, in_flight: in_flight}
    end
  end

  def self.expire_messages(messages)
    # Change visiblity batch is limited to 10 requests per batch
    messages.each_slice(10) do |message_batch|
      sqs.change_message_visibility_batch({
        queue_url: message_batch.first[:queue][:url],
        entries: message_batch.map do |message| 
          {id: message[:message].message_id, receipt_handle: message[:message].receipt_handle, visibility_timeout: 0}
        end
      })
    end
  end

  def self.move_message_to_queue(message, options)
    options[:poller].change_message_visibility_timeout(message, 30)
    sqs.send_message(queue_url: options[:destination_queue_url], message_body: message.body, message_attributes: message.message_attributes)
    "Message ID: #{options[:message_id]} in Queue #{options[:queue_name]} was successfully moved to Source Queue #{options[:destination_queue_url]}." if options[:poller].delete_message(message).successful?
  end

  def self.delete_message(message, options)
    "Message ID: #{options[:message_id]} in Queue #{options[:queue][:name]} was successfully removed." if options[:poller].delete_message(message).successful?
  end

  def self.process_action_by_message(message, options)
     options[:flash_message].message = if options[:action] == :remove
        delete_message(message, options)
    elsif options[:action] == :requeue
      move_message_to_queue(message,
        {destination_queue_url: options[:queue][:source_url], poller: options[:poller], 
          message_id: options[:message_id], queue_name: options[:queue][:name]}
      )
    end
  end
end