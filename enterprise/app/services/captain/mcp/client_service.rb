# Invokes an approved assistant tool from a playbook. Reuses the MCP registry, credential handling and safe transport.
class Captain::Mcp::ClientService
  class Rejected < StandardError; end

  MAX_RESULT_BYTES = 16.kilobytes
  UNAVAILABLE = 'This MCP tool is unavailable or no longer matches its approved definition.'.freeze

  def initialize(server, conversation:)
    @server = server
    @conversation = conversation
  end

  def approved_tool(tool_name)
    return unless @server&.enabled? && @server.active?
    return unless @server.account.feature_enabled?(Captain::McpServer::FEATURE_FLAG)
    return unless @conversation&.account_id == @server.account_id

    @server.available_tools.find_by(name: tool_name, account_id: @server.account_id)
  end

  def call_tool(tool_name, arguments = {}, expected_digest: nil, before_call: nil)
    tool = approved_tool(tool_name)
    validate_approval!(tool, expected_digest)
    filled_arguments = fill_arguments(tool, arguments)
    connection = connect_to_approved_tool(tool)

    rejection = before_call&.call
    return failure(rejection) if rejection

    execute_tool(connection, tool, filled_arguments)
  rescue Rejected, Captain::ParamSources::Unavailable => e
    failure(e.message)
  rescue *Captain::Mcp::Connection::ERRORS
    failure('Could not check the approved MCP tool with its server.')
  end

  private

  def validate_approval!(tool, expected_digest)
    raise Rejected, UNAVAILABLE unless tool
    raise Rejected, UNAVAILABLE if expected_digest && expected_digest != tool.approved_digest
    raise Rejected, 'This MCP tool needs approval before it can change data.' if !tool.read_only? && expected_digest.nil?
  end

  def fill_arguments(tool, arguments)
    raise Rejected, 'MCP arguments must be an object.' unless arguments.is_a?(Hash)

    filled = Captain::ToolArguments.new(tool, @conversation).fill(arguments.symbolize_keys)
    raise Rejected, 'MCP arguments do not match the approved schema.' unless valid_arguments?(tool, filled)

    filled
  end

  def connect_to_approved_tool(tool)
    approval = approval_configuration(tool)
    connection = Captain::Mcp::Connection.new(@server)
    definition = @server.refresh_live_tools(connection).find { |entry| entry.fetch('name') == tool.name }
    raise Rejected, UNAVAILABLE unless tool.review_state_for(definition) == 'current' && approval_still_current?(tool.name, approval)

    connection
  end

  def valid_arguments?(tool, arguments)
    JSONSchemer.schema(tool.input_schema).valid?(arguments.deep_stringify_keys)
  rescue JSONSchemer::UnknownRef, JSONSchemer::InvalidRefResolution, JSONSchemer::UnsupportedMetaSchema, JSONSchemer::InvalidRegexpResolution
    false
  end

  # A listing can take time. Check the decision is still valid after the response comes back.
  def approval_still_current?(name, approval)
    @server.reload
    current_tool = approved_tool(name)
    current_tool && approval_configuration(current_tool) == approval
  rescue ActiveRecord::RecordNotFound
    false
  end

  def approval_configuration(tool)
    [tool.id, tool.approved_digest, tool.param_sources, tool.settings, @server.url, @server.auth_type, @server.auth_header, @server.auth_config]
  end

  def execute_tool(connection, tool, arguments)
    result = connection.track_status { connection.call(tool.name, arguments) }
    return failure('The MCP server reported a tool error.') if result.error?

    { success: true, content: bounded_content(result) }
  rescue *Captain::Mcp::Connection::ERRORS
    return failure('The MCP server did not return a usable response.') if tool.read_only?

    failure('The MCP call may have run. Check the outcome before retrying.', outcome_unknown: true)
  end

  def bounded_content(result)
    content = result.structured || result.text
    serialized = content.is_a?(String) ? content : content.to_json
    return content if serialized.bytesize <= MAX_RESULT_BYTES

    serialized.byteslice(0, MAX_RESULT_BYTES).scrub
  end

  def failure(message, outcome_unknown: false)
    { success: false, error: message, outcome_unknown: outcome_unknown }
  end
end
