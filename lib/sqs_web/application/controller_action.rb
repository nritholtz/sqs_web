module ControllerAction
  def process_page_single_request(options={})
    result = messages({action: options[:action].to_sym, message_id: options[:params][:message_id], queue_name: options[:params][:queue_name]})
    flash_message.message = "Message ID: #{options[:params][:message_id]} in Queue #{options[:params][:queue_name]} has already been deleted or is not visible." if result.empty?
  end

  def process_page_bulk_request(options={})
    options[:params]["message_collection"].map!{|c| {message_id: c.split('/', 2)[0], queue_name: c.split('/', 2)[1]}}
    result = messages({action: options[:action].to_sym, messages: options[:params]["message_collection"], bulk_action: true})
    flash_message.message = if result.select{|c| c[:deleted]}.size != options[:params]["message_collection"].size
      "One or more messages may have already been #{options[:action]}d or is not visible."
    else
      "Selected messages have been #{options[:action]}d successfully."
    end
  end
end