require 'integration_helper'
require 'rack/test'
require_relative '../../../app/web_app'

RSpec.describe App do
  include Rack::Test::Methods

  def app
    described_class
  end

  it 'serves the root endpoint without starting bot runtime' do
    get '/'

    expect(last_response).to be_ok
    expect(last_response.body).to eq('Velo Utro Bot')
  end

  it 'serves the about page' do
    get '/about'

    expect(last_response).to be_ok
    expect(last_response.body).to include('<h1>Velo Utro Bot</h1>')
  end

  it 'does not expose the removed publish-today endpoint' do
    get '/publish-today-events'

    expect(last_response).to be_not_found
  end
end
