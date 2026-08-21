class App < Sinatra::Base
  register Sinatra::ActiveRecordExtension

  configure do
    set :root, VELO_UTRO_ROOT
    set :public_folder, File.join(settings.root, 'public')
    set :views, File.join(settings.root, 'app', 'views')
    set :port, APP_CONFIG.port
    set :bind, '0.0.0.0'
  end

  get '/' do
    'Velo Utro Bot'
  end

  get '/about' do
    <<~HTML
      <h1>Velo Utro Bot</h1>
      <b>© Aldushkin Nikita, 2025</b>
    HTML
  end

  get '/publish-today-events' do
    events = Event.today

    if events.empty?
      'No events scheduled for today.'
    else
      "#{events.length} events published successfully."
    end
  rescue => e
    "An error occurred while publishing events: #{e.message}"
  end
end
