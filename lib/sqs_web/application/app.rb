require 'sinatra/base'
require 'active_support'
require 'aws-sdk'

class SqsWeb < Sinatra::Base
  include Navigation

  class << self
    def options
      @@options ||= {queues: [], aws: {region: ENV['AWS_REGION'] || 'us-east-1'}}
    end
  end

  helpers do
    def flash_message
      @flash_message ||= FlashMessage.new(session)
    end
  end

  set :root, File.dirname(__FILE__)
  set :static, true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :views, File.expand_path('../views', __FILE__)
  set :show_exceptions, false

  error Exception do |exception|
    @error = ExceptionHandle.new(exception)
    erb :error
  end

  # Enable sessions so we can use CSRF protection
  enable :sessions

  set :protection,
    # Various session protections
    :session => true,
    # Various non-default Rack::Protection options
    :use => [
      # Prevent destructive actions without a valid CSRF auth token
      :authenticity_token,
      # Prevent destructive actions with remote referrers
      :remote_referrer
    ],
    # Deny the request, don't clear the session
    :reaction => :deny

  get '/overview' do
    @stats = queue_stats
    erb :overview
  end

  get "/dlq_console" do
    @messages = messages
    erb :dlq_console
  end

  %w(remove requeue).each do |action|
    post "/#{action}/:queue_name/:message_id" do
      process_page_single_request(action, params)
    end
  end

  %w(bulk_remove bulk_requeue).each do |action|
    post "/#{action}" do
      process_page_bulk_request(action.split('bulk_')[1], params) if params["message_collection"]
      redirect back
    end
  end

  get "/?" do
    redirect u(:overview)
  end

  private
  def process_page_single_request(action, params)
    result = messages({action: action.to_sym, message_id: params[:message_id], queue_name: params[:queue_name]})
    flash_message.message = "Message ID: #{params[:message_id]} in Queue #{params[:queue_name]} has already been deleted or is not visible." if result.empty?
    redirect back
  end

  def process_page_bulk_request(action, params)
    params["message_collection"].map!{|c| {message_id: c.split('/', 2)[0], queue_name: c.split('/', 2)[1]}}
    result = messages({action: action.to_sym, messages: params["message_collection"], bulk_action: true})
    flash_message.message = if result.select{|c| c[:deleted]}.size != params["message_collection"].size
      "One or more messages may have already been #{action}d or is not visible."
    else
      "Selected messages have been #{action}d successfully."
    end
  end

  def queue_stats
    @queues ||= AwsAction.load_queue_urls
    AwsAction.get_queue_stats(@queues)
  end

  def messages(options={})
    @queues ||= AwsAction.load_queue_urls
    @queues.select{|queue| queue[:source_url]}.each_with_object([]) do |queue, messages_result|
      poll_by_queue_and_result_and_options(queue, messages_result, options)
      AwsAction.expire_messages(messages_result.reject{|c| c[:deleted]})
    end
  end

  def poll_by_queue_and_result_and_options(queue, result, options)
    poller = Aws::SQS::QueuePoller.new(queue[:url], {client: AwsAction.sqs, skip_delete: true, idle_timeout: 0.2, 
     wait_time_seconds: 0, visibility_timeout: options[:visibility_timeout] || 5 })
    Timeout::timeout(30) do
      poller.poll do |message|
        process_message_by_result_and_options(result, 
          options.merge({ poller: poller, message: message, queue: queue})
        )
      end
    end
  end

  def process_message_by_result_and_options(result, options)
    if message_match(options)
      AwsAction.process_action_by_message(options[:message], 
        options.merge({flash_message: flash_message})
      )
      signal_deleted_message(result, options)
    else
      result << {message: options[:message], queue: options[:queue]}
    end
  end

  def message_match(options)
    if options[:bulk_action]
      options[:messages].find{|message| match_message_by_options(message[:message_id], message[:queue_name], options)}
    else
      options[:action] && match_message_by_options(options[:message_id], options[:queue_name], options)
    end
  end

  def match_message_by_options(message_id, queue_name, options)
    message_id == options[:message].message_id && queue_name == options[:queue][:name]
  end

  def signal_deleted_message(result, options)
    result << {message: options[:message], queue: options[:queue], deleted: true}
    throw :stop_polling unless (options[:messages] && result.select{|c| c[:deleted]}.size < options[:messages].size)
  end
end
