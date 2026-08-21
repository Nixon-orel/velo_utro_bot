require_relative 'config/environment'

migrations_path = File.join(VELO_UTRO_ROOT, 'db', 'migrations')
ActiveRecord::MigrationContext.new(migrations_path).migrate
AppLogger.info('Migration', 'Migrations completed')
