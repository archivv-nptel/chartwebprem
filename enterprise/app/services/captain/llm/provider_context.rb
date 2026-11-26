# Tenant credentials stay in a per-request RubyLLM context. The locked RubyLLM adapter
# implements authentication, message formats, and tool calls for all four providers.
class Captain::Llm::ProviderContext
  PROVIDERS = {
    'aws_bedrock' => :bedrock,
    'azure_openai' => :azure,
    'google_vertex' => :vertexai,
    'openai_compatible' => :openai
  }.freeze

  def initialize(provider_config)
    @provider_config = provider_config
  end

  def chat(model: @provider_config.model_id)
    chat = Captain::Llm::ProviderChat.new(model: model, provider: PROVIDERS.fetch(@provider_config.provider_type),
                                          assume_model_exists: true, context: context)
    max_tokens = @provider_config.routing_rules['max_tokens']
    chat.with_max_output_tokens(max_tokens) if max_tokens
    chat
  end

  private

  def context
    credentials = @provider_config.credentials
    RubyLLM.context do |config|
      config.faraday_adapter = Captain::Llm::ProviderTransport
      config.request_timeout = 12
      config.max_retries = 0
      config.instrumenter = nil
      configure_provider(config, credentials)
    end
  end

  def configure_provider(config, credentials)
    case @provider_config.provider_type
    when 'aws_bedrock' then configure_bedrock(config, credentials)
    when 'azure_openai'
      config.azure_api_base = azure_api_base
      config.azure_api_key = credentials.fetch('api_key')
    when 'google_vertex' then configure_vertex(config, credentials)
    when 'openai_compatible'
      config.openai_api_base = @provider_config.endpoint_url
      config.openai_api_key = credentials.fetch('api_key', Captain::Llm::ProviderTransport::NO_AUTH_KEY)
      config.openai_organization_id = nil
      config.openai_project_id = nil
      config.openai_protocol = :chat_completions
    end
  end

  def azure_api_base
    endpoint = URI.parse(@provider_config.endpoint_url)
    return endpoint.to_s unless endpoint.host.end_with?('.openai.azure.com') && ['', '/'].include?(endpoint.path)

    endpoint.path = '/openai/v1'
    endpoint.to_s
  end

  def configure_bedrock(config, credentials)
    config.bedrock_api_key = credentials.fetch('aws_access_key_id')
    config.bedrock_secret_key = credentials.fetch('aws_secret_access_key')
    config.bedrock_session_token = credentials['aws_session_token']
    config.bedrock_region = @provider_config.region
    config.bedrock_credential_provider = nil
    config.bedrock_api_base = nil
    config.bedrock_mantle_api_base = nil
  end

  def configure_vertex(config, credentials)
    config.vertexai_project_id = credentials.fetch('project_id')
    config.vertexai_location = @provider_config.region
    config.vertexai_service_account_key = credentials.fetch('service_account_key').to_json
    config.vertexai_api_base = nil
  end
end
