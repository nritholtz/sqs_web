require 'sinatra/base'
require 'active_support'
require 'aws-sdk'

class SqsWeb < Sinatra::Base

  class << self
    def options
      @@options ||= {queues: [], aws: {region: ENV['AWS_REGION'] || 'us-east-1'}}
    end
  end

  class FlashMessage
    def initialize(session)
      @session ||= session
    end

    def message=(message)
      @session[:flash] = message
    end

    def message
      message = @session[:flash] #tmp get the value
      @session[:flash] = nil # unset the value
      message # display the value
    end
  end

  helpers do
    def flash
      @flash ||= FlashMessage.new(session)
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

  def current_page
    url_path request.path_info.sub('/','')
  end

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
      {:name => 'Enqueued', :path => '/enqueued'}
    ]
  end

  def sqs
    return @sqs if @sqs
    initialize_aws
    @sqs = Aws::SQS::Client.new(aws_client_options)
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

  %w(overview enqueued).each do |page|
    get "/#{page}" do
      @messages = sqs && messages
      erb page.to_sym
    end
  end

  post "/remove/:queue_name/:message_id" do
    result = messages({visibility_timeout: 4, action: :delete, message_id: params[:message_id], queue_name: params[:queue_name]})
    flash.message = "Message ID: #{params[:message_id]} in Queue #{params[:queue_name]} has already been deleted or no longer exists." if result.empty?
    redirect back
  end

  # %w(pending failed).each do |page|
  #   post "/requeue/#{page}" do
  #     delayed_jobs(page.to_sym, @queues).update_all(:run_at => Time.now, :failed_at => nil)
  #     redirect back
  #   end
  # end

  # post "/requeue/:id" do
  #   job = delayed_job.find(params[:id])
  #   job.update_attributes(:run_at => Time.now, :failed_at => nil)
  #   redirect back
  # end

  # post "/reload/:id" do
  #   job = delayed_job.find(params[:id])
  #   job.update_attributes(:run_at => Time.now, :failed_at => nil, :locked_by => nil, :locked_at => nil, :last_error => nil, :attempts => 0)
  #   redirect back
  # end

  # post "/failed/clear" do
  #   delayed_jobs(:failed, @queues).delete_all
  #   redirect u('failed')
  # end

  # def delayed_jobs(type, queues = [])
  #   rel = delayed_job

  #   rel =
  #     case type
  #     when :working
  #       rel.where('locked_at IS NOT NULL')
  #     when :failed
  #       rel.where('last_error IS NOT NULL')
  #     when :pending
  #       rel.where(:attempts => 0, :locked_at => nil)
  #     else
  #       rel
  #     end

  #   rel = rel.where(:queue => queues) unless queues.empty?

  #   rel
  # end

  get "/?" do
    redirect u(:overview)
  end

  def partial(template, local_vars = {})
    @partial = true
    erb(template.to_sym, {:layout => false}, local_vars)
  ensure
    @partial = false
  end

  # %w(overview enqueued working pending failed stats) .each do |page|
  #   get "/#{page}.poll" do
  #     show_for_polling(page)
  #   end

  #   get "/#{page}/:id.poll" do
  #     show_for_polling(page)
  #   end
  # end

  # def poll
  #   if @polling
  #     text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
  #   else
  #     text = "<a href='#{u(request.path_info + ".poll")}' rel='poll'>Live Poll</a>"
  #   end
  #   "<p class='poll'>#{text}</p>"
  # end

  # def show_for_polling(page)
  #   content_type "text/html"
  #   @polling = true
  #   # show(page.to_sym, false).gsub(/\s{1,}/, ' ')
  #   @jobs = delayed_jobs(page.to_sym, @queues)
  #   erb(page.to_sym, {:layout => false})
  # end

  private

  def messages(options={})
    messages_result = []
    load_queue_urls unless @queues
    @queues.each do |queue|
      eval "@poller_#{queue[:name]} ||= Aws::SQS::QueuePoller.new(queue[:url], {client: sqs, skip_delete: true, idle_timeout: 1, 
        wait_time_seconds: 1, visibility_timeout: options[:visibility_timeout] || 5})"
      Timeout::timeout(30) do
        instance_variable_get("@poller_#{queue[:name]}").poll do |message|
          if options[:action] == :delete 
            if options[:message_id] == message.message_id && options[:queue_name] == queue[:name]
              response = instance_variable_get("@poller_#{queue[:name]}").delete_message(message)
              if response.successful?
                flash.message = "Message ID: #{options[:message_id]} in Queue #{options[:queue_name]} was successfully removed."
              else
                flash.message = "Error while trying to delete Message ID: #{options[:message_id]} in Queue #{options[:queue_name]}: #{response.inspect}"
              end
              messages_result << {message: message, queue: queue}
              throw :stop_polling
            end            
          else
            messages_result << {message: message, queue: queue}
          end
        end
      end
    end
    messages_result
  end

  def aws_client_options
    options = {}
    options[:endpoint] = SqsWeb.options[:aws][:endpoint] if SqsWeb.options[:aws][:endpoint]
    options
  end

  def initialize_aws
    # aws-sdk tries to load the credentials from the ENV variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
    # when not explicit supplied
    return if SqsWeb.options[:aws].empty?

    aws_options = SqsWeb.options[:aws]

    # assume credentials based authentication
    credentials = Aws::Credentials.new(
      aws_options.delete(:access_key_id),
      aws_options.delete(:secret_access_key))

    # but only if the configuration options have valid values
    aws_options = aws_options.merge(credentials: credentials) if credentials.set?

    Aws.config = aws_options
    Aws::SQS::Client.remove_plugin(Aws::Plugins::SQSQueueUrls) if Rails.env.test?
  end

  def load_queue_urls
    @queues = sqs && SqsWeb.options[:queues].map do |queue_name|
      queue_url = sqs.get_queue_url(queue_name: queue_name).queue_url
      queue_url.gsub!('0.0.0.0', 'dockerhost') if Rails.env.test?
      {name: queue_name, url: queue_url}
    end
  end

  def parse_error_message(error)
    @error_class = error.inspect.to_s
    @error_message = error.message.to_s
    @error_backtrace = error.backtrace.to_s
  end
end
