# A custom tool in a conversation where a customer is the user. A tool that needs a verified customer runs only
# for a customer who verified an email, and a verified email parameter always carries that email.
class Captain::Tools::PublicHttpTool < Captain::Tools::HttpTool
  include Captain::Hitl::PublicToolGate

  def perform(tool_context, **params)
    request_mutation_approval(@custom_tool, tool_context, params) || super
  rescue Captain::ParamSources::Unavailable => e
    failure_result(e.message, tool_context.state)
  end

  # Called only after the approval has been claimed and its tool definition revalidated.
  def execute_approved!(tool_context, **params)
    arguments = arguments_for(tool_context, params)
    url = @custom_tool.build_request_url(arguments)
    body = @custom_tool.build_request_body(arguments)
    @custom_tool.format_response(execute_http_request(url, body, tool_context))
  end

  private

  def arguments_for(tool_context, params)
    return params unless @custom_tool.requires_verified_customer?

    verified_email = Captain::ParamSources.verified_email(find_conversation(tool_context.state))
    # Set last, so a value from the model can never replace the verified email
    email_param = @custom_tool.verified_email_param
    email_param ? params.merge(email_param.to_sym => verified_email) : params
  end
end
