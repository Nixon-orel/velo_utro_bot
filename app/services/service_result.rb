class ServiceResult
  attr_reader :value, :error_code, :error, :metadata

  def self.success(value = nil, **metadata)
    new(success: true, value: value, metadata: metadata)
  end

  def self.failure(error_code, error: nil, value: nil, **metadata)
    new(success: false, value: value, error_code: error_code, error: error, metadata: metadata)
  end

  def initialize(success:, value:, metadata:, error_code: nil, error: nil)
    @success = success
    @value = value
    @metadata = metadata.freeze
    @error_code = error_code
    @error = error
  end

  def success?
    @success
  end

  def failure?
    !success?
  end
end
