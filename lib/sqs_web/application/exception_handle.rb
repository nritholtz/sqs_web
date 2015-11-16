class ExceptionHandle
  attr_reader :error_class, :error_message, :error_backtrace

  def initialize(error)
    @error_class = error.inspect.to_s
    @error_message = error.message.to_s
    @error_backtrace = error.backtrace.to_s
  end
end