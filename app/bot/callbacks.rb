require_relative 'base_handler'
require_relative 'callback_handler'

module Bot
  module Callbacks
    Dir[File.join(File.dirname(__FILE__), 'callbacks', '*.rb')].each do |file|
      require file
    end
    
    def self.process(callback_data, bot, callback, session)
      action = callback_data.split('-')[0]
      
      callback_class = action.capitalize
      
      unless const_defined?(callback_class)
        callback_class = action.split('_').map(&:capitalize).join('_')
      end
      
      if const_defined?(callback_class)
        const_get(callback_class).new(bot, callback, session).process
      else
        bot.api.answer_callback_query(
          callback_query_id: callback.id,
          text: I18n.t('unknown_command'),
          show_alert: true
        )
      end
    end
  end
end