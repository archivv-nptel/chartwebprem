# Apply the same DNS pinning as MCP. Buffer only bounded JSON responses.
class Captain::Llm::ProviderTransport < Captain::Mcp::SafeFaradayAdapter
  NO_AUTH_KEY = 'captain-byom-no-auth'.freeze

  def call(env)
    env.request_headers.delete('Authorization') if env.request_headers['Authorization'] == "Bearer #{NO_AUTH_KEY}"
    super
  end

  def perform_request(http, env)
    return super if env.stream_response?

    body = +''
    env.request.on_data = ->(chunk, *) { body << chunk }
    response = super
    env.response_body = body
    response
  end
end
