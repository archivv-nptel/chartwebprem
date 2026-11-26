class Captain::LlmProviderConfig < ApplicationRecord
  self.table_name = 'captain_llm_provider_configs'

  PROVIDERS = %w[aws_bedrock azure_openai google_vertex openai_compatible].freeze
  CREDENTIAL_FIELDS = {
    'aws_bedrock' => %w[aws_access_key_id aws_secret_access_key aws_session_token],
    'azure_openai' => %w[api_key],
    'google_vertex' => %w[project_id service_account_key],
    'openai_compatible' => %w[api_key]
  }.freeze
  HTTPS_PROVIDERS = %w[azure_openai openai_compatible].freeze
  REGION_PATTERN = /\A[a-z]+(?:-[a-z0-9]+){1,4}\z/
  VERTEX_REGION_PATTERN = /\A(?:[a-z]+-[a-z]+[0-9]+|global)\z/

  belongs_to :account

  attribute :zero_data_retention, :boolean, default: false
  encrypts :encrypted_credentials

  validates :name, :model_id, presence: true, length: { maximum: 255 }
  validates :model_id, format: { with: %r{\A[\w.-]+[\w.:/-]*\z} }, exclusion: { in: %w[. ..] }
  validates :provider_type, inclusion: { in: PROVIDERS }
  validates :enabled, :zero_data_retention, inclusion: { in: [true, false] }
  validates :priority, numericality: { only_integer: true, in: 1..1000 }
  validates :region, format: { with: REGION_PATTERN }, if: -> { provider_type == 'aws_bedrock' }
  validates :region, format: { with: VERTEX_REGION_PATTERN }, if: -> { provider_type == 'google_vertex' }
  validate :validate_model_path
  validate :validate_endpoint
  validate :validate_credentials
  validate :validate_routing_rules

  scope :ordered_active, -> { where(enabled: true).order(:priority, :id) }

  def credentials
    @pending_credentials || JSON.parse(encrypted_credentials.presence || '{}')
  end

  def credentials=(value)
    @pending_credentials = value
  end

  def credentials_configured?
    # Read the raw attribute: serialization must never decrypt or expose a secret.
    encrypted_credentials_before_type_cast.present?
  end

  def reload(...)
    @pending_credentials = nil
    super
  end

  private

  before_save :write_credentials
  after_save :clear_pending_credentials

  def write_credentials
    return unless @pending_credentials

    self.encrypted_credentials = @pending_credentials.presence&.to_json
  end

  def clear_pending_credentials
    @pending_credentials = nil
  end

  def validate_model_path
    value = model_id.to_s
    errors.add(:model_id, :invalid) if value.include?('//') || value.split('/').intersect?(%w[. ..])
  end

  def validate_endpoint
    valid = HTTPS_PROVIDERS.include?(provider_type) ? valid_https_endpoint? : endpoint_url.blank?
    errors.add(:endpoint_url, :invalid) unless valid
  end

  def valid_https_endpoint?
    endpoint = URI.parse(endpoint_url.to_s)
    endpoint.is_a?(URI::HTTPS) && endpoint.host.present? && [endpoint.userinfo, endpoint.fragment, endpoint.query].all?(&:nil?)
  rescue URI::InvalidURIError
    false
  end

  def validate_credentials
    if @pending_credentials.present? && !Chatwoot.encryption_configured?
      errors.add(:credentials, :encryption_unavailable)
      return
    end

    value = credentials
    return if value.is_a?(Hash) && valid_credentials?(value)

    errors.add(:credentials, :invalid)
  end

  def valid_credentials?(value)
    return false if (value.keys - CREDENTIAL_FIELDS.fetch(provider_type, [])).any?

    case provider_type
    when 'aws_bedrock' then valid_string_credentials?(value, %w[aws_access_key_id aws_secret_access_key])
    when 'azure_openai' then valid_string_credentials?(value, %w[api_key])
    when 'google_vertex' then valid_vertex_credentials?(value)
    else valid_string_credentials?(value, [])
    end
  end

  def valid_string_credentials?(value, required_keys)
    required_keys.all? { |key| value.key?(key) } &&
      value.values.all? { |item| item.is_a?(String) && item.present? && item.bytesize <= 4096 && !item.match?(/[[:cntrl:]]/) }
  end

  def valid_vertex_credentials?(value)
    project = value['project_id']
    key = value['service_account_key']
    return false unless project.is_a?(String) && project.match?(/\A[a-z][a-z0-9-]{4,62}[a-z0-9]\z/)
    return false unless key.is_a?(Hash) && (key.keys - %w[client_email private_key]).empty?

    valid_service_account_key?(key)
  end

  def valid_service_account_key?(key)
    email = key['client_email']
    private_key = key['private_key']
    email.is_a?(String) && email.match?(/\A[^@\s]+@[^@\s]+\.gserviceaccount\.com\z/) &&
      private_key.is_a?(String) && private_key.bytesize <= 8192 && OpenSSL::PKey::RSA.new(private_key).private?
  rescue OpenSSL::PKey::PKeyError
    false
  end

  def validate_routing_rules
    rules = routing_rules
    valid = rules.is_a?(Hash) && (rules.keys - %w[task max_tokens]).empty? && valid_task?(rules) && valid_token_limit?(rules)
    errors.add(:routing_rules, :invalid) unless valid
  end

  def valid_task?(rules)
    !rules.key?('task') || ::Llm::Models.feature?(rules['task'])
  end

  def valid_token_limit?(rules)
    !rules.key?('max_tokens') || (rules['max_tokens'].is_a?(Integer) && rules['max_tokens'].between?(1, 32_768))
  end
end
