class Captain::Mcp::ServerDispatcher
  INITIALIZE_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26].freeze
  PROTOCOL_VERSIONS = ['2026-07-28', *INITIALIZE_VERSIONS].freeze
  STATIC_RESULTS = {
    'ping' => {},
    'tools/list' => { tools: Captain::Mcp::ConversationTools::TOOLS },
    'resources/list' => { resources: [] },
    'resources/templates/list' => { resourceTemplates: [Captain::Mcp::ConversationTools::RESOURCE_TEMPLATE] }
  }.freeze

  def initialize(account:, user:, account_user:)
    @tools = Captain::Mcp::ConversationTools.new(account: account, user: user, account_user: account_user)
  end

  def dispatch(payload)
    return error(nil, -32_600, 'Invalid request') unless valid_request?(payload)
    return unless payload.key?('id')

    id = payload.fetch('id')
    result = dispatch_method(payload.fetch('method'), payload.fetch('params', {}), id)
    return result if result.key?(:error)

    { jsonrpc: '2.0', id: id, result: result }
  rescue Captain::Mcp::ConversationTools::InvalidArguments
    error(id, -32_602, 'Invalid params')
  rescue ActiveRecord::RecordNotFound
    error(id, -32_002, 'Resource not found')
  rescue ActiveRecord::RecordInvalid
    error(id, -32_000, 'The operation could not be saved')
  end

  def self.parse_error
    { jsonrpc: '2.0', id: nil, error: { code: -32_700, message: 'Parse error' } }
  end

  private

  def valid_request?(payload)
    payload.is_a?(Hash) && payload['jsonrpc'] == '2.0' && payload['method'].is_a?(String) && payload['method'].present? &&
      payload.fetch('params', {}).is_a?(Hash) && (!payload.key?('id') || valid_id?(payload['id']))
  end

  def valid_id?(id)
    id.is_a?(Integer) || id.is_a?(String)
  end

  def dispatch_method(method, params, id)
    return STATIC_RESULTS.fetch(method) if STATIC_RESULTS.key?(method)

    case method
    when 'server/discover' then server_metadata.merge(supportedVersions: PROTOCOL_VERSIONS)
    when 'initialize' then server_info(params)
    when 'tools/call' then call_tool(params)
    when 'resources/read' then read_resource(params)
    else error(id, -32_601, 'Method not found')
    end
  end

  def server_info(params)
    requested_version = params['protocolVersion']
    raise Captain::Mcp::ConversationTools::InvalidArguments unless requested_version.is_a?(String)

    version = INITIALIZE_VERSIONS.include?(requested_version) ? requested_version : INITIALIZE_VERSIONS.first
    server_metadata.merge(protocolVersion: version)
  end

  def server_metadata
    {
      capabilities: { tools: {}, resources: {} },
      serverInfo: { name: 'Chatwoot Enterprise MCP Server', version: Chatwoot.config[:version] }
    }
  end

  def call_tool(params)
    output = @tools.call(params['name'], params.fetch('arguments', {}))
    { content: [{ type: 'text', text: output.to_json }] }
  end

  def read_resource(params)
    uri = params['uri']
    raise Captain::Mcp::ConversationTools::InvalidArguments unless uri.is_a?(String)

    { contents: [{ uri: uri, mimeType: 'application/json', text: @tools.read(uri).to_json }] }
  end

  def error(id, code, message)
    { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
  end
end
