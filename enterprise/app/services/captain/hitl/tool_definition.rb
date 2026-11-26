module Captain::Hitl::ToolDefinition
  CUSTOM_CONFIGURATION = %w[endpoint_url http_method param_schema request_template response_template settings headers auth_type auth_config].freeze

  def self.digest(tool)
    case tool
    when Captain::McpTool
      Digest::SHA256.hexdigest(JSON.generate([tool.approved_digest, tool.param_sources, tool.settings, tool.mcp_server.url]))
    when Captain::CustomTool
      Digest::SHA256.hexdigest(JSON.generate(tool.attributes.slice(*CUSTOM_CONFIGURATION)))
    else
      raise ArgumentError, 'Unknown approval tool'
    end
  end

  def self.identifier(tool)
    tool.is_a?(Captain::McpTool) ? tool.captain_name : tool.slug
  end
end
