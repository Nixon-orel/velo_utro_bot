require 'database_cleaner/active_record'

module TestDatabaseSafety
  module_function

  def verify!
    environment = APP_CONFIG.environment
    database = ActiveRecord::Base.connection_db_config.database.to_s

    raise "Integration specs require RACK_ENV=test, got #{environment.inspect}" unless environment == 'test'
    raise "Integration specs refuse database #{database.inspect}" unless database.end_with?('_test')
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    TestDatabaseSafety.verify!

    migrations_path = File.join(VELO_UTRO_ROOT, 'db', 'migrations')
    ActiveRecord::MigrationContext.new(migrations_path).migrate
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around do |example|
    DatabaseCleaner.strategy = example.metadata[:concurrent] ? :truncation : :transaction
    DatabaseCleaner.cleaning { example.run }
  end
end
