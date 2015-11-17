require 'sinatra/base'
require 'active_support'
require 'aws-sdk'

class SqsWeb < Sinatra::Base
  include Navigation
  include ControllerAction

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
      process_page_single_request(action: action, params: params)
      redirect back
    end
  end

  %w(bulk_remove bulk_requeue).each do |action|
    post "/#{action}" do
      process_page_bulk_request(action: action.split('bulk_')[1], params: params) if params["message_collection"]
      redirect back
    end
  end

  get "/?" do
    redirect u(:overview)
  end

  private
  def queue_stats
    @queues ||= SqsAction.load_queue_urls
    SqsAction.get_queue_stats(@queues)
  end

  def messages(options={})
    @queues ||= SqsAction.load_queue_urls
    @queues.select{|queue| queue[:source_url]}.each_with_object([]) do |queue, messages_result|
      PollerAction.poll_by_queue_and_result_and_options(queue, messages_result, options.merge(flash_message: flash_message))
      SqsAction.expire_messages(messages_result.reject{|c| c[:deleted]})
    end
  end
end
