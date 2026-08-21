module AppLogger
  class << self
    def debug(component, message, **context)
      write(:debug, component, message, context)
    end

    def info(component, message, **context)
      write(:info, component, message, context)
    end

    def warn(component, message, **context)
      write(:warn, component, message, context)
    end

    def error(component, message, exception: nil, **context)
      context[:error_class] = exception.class.name if exception
      context[:error] = exception.message if exception
      write(:error, component, message, context)
      APP_LOGGER.debug(exception.backtrace.join("\n")) if exception&.backtrace && APP_LOGGER.debug?
    end

    private

    def write(level, component, message, context)
      details = context.compact.map { |key, value| "#{key}=#{value.inspect}" }.join(' ')
      text = "[#{component}] #{message}"
      text = "#{text} #{details}" unless details.empty?
      APP_LOGGER.public_send(level, text)
    end
  end
end
