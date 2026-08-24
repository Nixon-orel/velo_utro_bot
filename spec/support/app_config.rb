module TestAppConfig
  def use_app_config(values)
    stub_const('APP_CONFIG', AppConfig.new(APP_CONFIG.to_h.merge(values.transform_keys(&:to_s))))
  end
end

RSpec.configure do |config|
  config.include TestAppConfig
end
