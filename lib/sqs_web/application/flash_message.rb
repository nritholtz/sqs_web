class FlashMessage
  def initialize(session)
    @session ||= session
  end

  def message=(message)
    @session[:flash_message] = message
  end

  def message
    message = @session[:flash_message] #tmp get the value
    @session[:flash_message] = nil # unset the value
    message # display the value
  end
end