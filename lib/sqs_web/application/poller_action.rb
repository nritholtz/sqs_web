class PollerAction
  
  protected
  def self.poll_by_queue_and_result_and_options(queue, result, options)
    poller = Aws::SQS::QueuePoller.new(queue[:url], {client: SqsAction.sqs, skip_delete: true, idle_timeout: 0.2, 
     wait_time_seconds: 0, visibility_timeout: options[:visibility_timeout] || 5 })
    Timeout::timeout(30) do
      poller.poll do |message|
        process_message_by_result_and_options(result, 
          options.merge({ poller: poller, message: message, queue: queue})
        )
      end
    end
  end

  def self.process_message_by_result_and_options(result, options)
    if message_match(options)
      SqsAction.process_action_by_message(options[:message], options)
      signal_deleted_message(result, options)
    else
      result << {message: options[:message], queue: options[:queue]}
    end
  end

  def self.message_match(options)
    if options[:bulk_action]
      options[:messages].find{|message| match_message_by_options(message[:message_id], message[:queue_name], options)}
    else
      options[:action] && match_message_by_options(options[:message_id], options[:queue_name], options)
    end
  end

  def self.match_message_by_options(message_id, queue_name, options)
    message_id == options[:message].message_id && queue_name == options[:queue][:name]
  end

  def self.signal_deleted_message(result, options)
    result << {message: options[:message], queue: options[:queue], deleted: true}
    throw :stop_polling unless (options[:messages] && result.select{|c| c[:deleted]}.size < options[:messages].size)
  end
end