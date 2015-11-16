require 'sinatra/base'
require 'active_support'
require 'aws-sdk'

class SqsWeb < Sinatra::Base

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
    parse_error_message(exception)
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

  # def current_page
  #   url_path request.path_info.sub('/','')
  # end

  def url_path(*path_parts)
    [ path_prefix, path_parts ].join("/").squeeze('/')
  end

  alias_method :u, :url_path

  def h(text)
    Rack::Utils.escape_html(text)
  end

  def path_prefix
    request.env['SCRIPT_NAME']
  end

  def tabs
    [
      {:name => 'Overview', :path => '/overview'},
      {:name => 'DLQ Console', :path => '/dlq_console'}
    ]
  end

  def sqs
    return @sqs if @sqs
    initialize_aws
    @sqs = Aws::SQS::Client.new
    load_queue_urls
    @sqs
  end

  def csrf_token
    # Set up by Rack::Protection
    session[:csrf]
  end

  def csrf_token_tag
    # If csrf_token is nil, and we submit a blank string authenticity_token
    # param, Rack::Protection will fail.
    if csrf_token
      "<input type='hidden' name='authenticity_token' value='#{h csrf_token}'>"
    end
  end

  get '/overview' do
    @stats = queue_stats
    erb :overview
  end

  get "/dlq_console" do
    @messages = sqs && messages
    erb :dlq_console
  end

  post "/remove/:queue_name/:message_id" do
    result = messages({action: :delete, message_id: params[:message_id], queue_name: params[:queue_name]})
    flash_message.message = "Message ID: #{params[:message_id]} in Queue #{params[:queue_name]} has already been deleted or is not visible." if result.empty?
    redirect back
  end

  post "/requeue/:queue_name/:message_id" do
    result = messages({action: :requeue, message_id: params[:message_id], queue_name: params[:queue_name]})
    flash_message.message = "Message ID: #{params[:message_id]} in Queue #{params[:queue_name]} has already been deleted or is not visible." if result.empty?
    redirect back
  end

  get "/?" do
    redirect u(:overview)
  end

  def partial(template, local_vars = {})
    @partial = true
    erb(template.to_sym, {:layout => false}, local_vars)
  ensure
    @partial = false
  end

  private
  def queue_stats
    load_queue_urls unless @queues
    @queues.each_with_object({}) do |queue, stats_summary|
      visible = in_flight = 0
      response = sqs.get_queue_attributes(queue_url: queue[:url], attribute_names: ["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"]).attributes
      visible += response["ApproximateNumberOfMessages"].to_i
      in_flight += response["ApproximateNumberOfMessagesNotVisible"].to_i
      stats_summary[queue[:name]] = {visible: visible, in_flight: in_flight}
    end
  end

  def messages(options={})
    load_queue_urls unless @queues
    @queues.select{|queue| queue[:source_url]}.each_with_object([]) do |queue, messages_result|
      poll_by_queue_and_result_and_options(queue, messages_result, options)
      expire_messages(messages_result.reject{|c| c[:deleted]})
    end
  end

  def poll_by_queue_and_result_and_options(queue, result, options)
    poller = Aws::SQS::QueuePoller.new(queue[:url], {client: sqs, skip_delete: true, idle_timeout: 0.2, 
     wait_time_seconds: 0, visibility_timeout: options[:visibility_timeout] || 5 })
    Timeout::timeout(30) do
      poller.poll do |message|
        process_message_by_result_and_poller_and_queue_and_options(result, poller, message, queue, options)
      end
    end
  end

  def expire_messages(messages)
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

  def process_message_by_result_and_poller_and_queue_and_options(result, poller, message, queue, options)
    if options[:action] == :delete && options[:message_id] == message.message_id && options[:queue_name] == queue[:name]
      set_flash_message_by_action_and_response_and_queue_and_options(:delete, poller.delete_message(message), queue, options)
      signal_deleted_message(result, message, queue)
    elsif options[:action] == :requeue && options[:message_id] == message.message_id && options[:queue_name] == queue[:name]
      set_flash_message_by_action_and_response_and_queue_and_options(:requeue, move_message_to_queue(message, queue[:source_url], poller), queue, options)
      signal_deleted_message(result, message, queue)
    else
      result << {message: message, queue: queue}
    end
  end

  def set_flash_message_by_action_and_response_and_queue_and_options(action, response, queue, options)
    if response.successful?
      flash_message.message = case action
      when :delete
        "Message ID: #{options[:message_id]} in Queue #{queue[:name]} was successfully removed."
      when :requeue
        "Message ID: #{options[:message_id]} in Queue #{queue[:name]} was successfully moved to Source Queue #{queue[:source_url]}."
      end
    end
  end

  def signal_deleted_message(result, message, queue)
    result << {message: message, queue: queue, deleted: true}
    throw :stop_polling
  end

  def move_message_to_queue(message, destination_queue_url, poller)
    poller.change_message_visibility_timeout(message, 30)
    sqs.send_message(queue_url: destination_queue_url, message_body: message.body, message_attributes: message.message_attributes)
    poller.delete_message(message)
  end

  def initialize_aws
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

  def load_queue_urls
    @queues = sqs && SqsWeb.options[:queues].map do |queue_name|
      dlq_queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
      source_queue_url = sqs.list_dead_letter_source_queues({queue_url: dlq_queue_url}).queue_urls.first
      {name:  queue_name, url: dlq_queue_url, source_url: source_queue_url}
    end
  end

  def parse_error_message(error)
    @error_class = error.inspect.to_s
    @error_message = error.message.to_s
    @error_backtrace = error.backtrace.to_s
  end
end
