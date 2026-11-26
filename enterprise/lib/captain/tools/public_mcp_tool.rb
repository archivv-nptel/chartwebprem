# An MCP tool in a conversation where a customer is the user. Parameters with a source always carry the value
# Chatwoot read, and the tool does not run when a value the customer must prove is missing.
class Captain::Tools::PublicMcpTool < Captain::Tools::McpTool
  include Captain::Hitl::PublicToolGate

  def perform(tool_context, **params)
    request_mutation_approval(@mcp_tool, tool_context, params) || super
  rescue Captain::ParamSources::Unavailable => e
    failure_result(e.message, tool_context.state)
  end

  private

  def arguments_for(tool_context, params)
    Captain::ToolArguments.new(@mcp_tool, find_conversation(tool_context.state)).fill(params)
  end
end
