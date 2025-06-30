require 'i18n'

I18n.load_path += Dir[File.join(File.dirname(__FILE__), '../locales/*.yml')]
I18n.default_locale = :ru
I18n.config.enforce_available_locales = false