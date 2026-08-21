require_relative 'config/environment'
require_relative 'app/web_app'
require_relative 'app/bot/runner'

if $PROGRAM_NAME == __FILE__
  if APP_CONFIG.production?
    App.run!
  else
    exit(Bot::Runner.run ? 0 : 1)
  end
end
