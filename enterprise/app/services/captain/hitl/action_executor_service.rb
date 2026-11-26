class Captain::Hitl::ActionExecutorService
  class Unavailable < StandardError; end

  TOOL_CONTEXT = Struct.new(:state)

  def self.reviewer_allowed?(approval, reviewer)
    membership = approval.account.account_users.find_by(user: reviewer)
    return false unless membership

    ConversationPolicy.new({ user: reviewer, account: approval.account, account_user: membership }, approval.conversation).show?
  end

  def approve_and_execute!(approval:, reviewer:, modified_arguments: nil)
    approval.with_lock do
      validate_review!(approval, reviewer)
      approval.update!(status: 'approved', reviewer: reviewer, reviewed_at: Time.current, modified_arguments: modified_arguments)
    end

    result = execute_tool(approval)
    approval.update!(status: result.fetch(:success) ? 'executed' : 'failed', execution_result: result, executed_at: Time.current)
    after_review(approval)
    approval
  end

  def reject!(approval:, reviewer:, reason:)
    approval.with_lock do
      validate_review!(approval, reviewer)
      approval.update!(status: 'rejected', reviewer: reviewer, reviewed_at: Time.current, rejection_reason: reason)
    end
    after_review(approval)
    approval
  end

  private

  def validate_review!(approval, reviewer)
    raise Pundit::NotAuthorizedError unless self.class.reviewer_allowed?(approval, reviewer)
    raise Unavailable, 'This request is no longer pending or has expired' unless approval.reviewable?
    raise Unavailable, 'The customer sent a newer message. Ask Captain to propose the action again.' if approval.newer_message_arrived?
  end

  def execute_tool(approval)
    tool = approval.mcp_tool || approval.custom_tool
    validate_tool!(approval, tool)
    tool.is_a?(Captain::McpTool) ? execute_mcp(approval, tool) : execute_custom(approval, tool)
  rescue Unavailable, Captain::ParamSources::Unavailable => e
    { success: false, error: e.message }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: approval.account).capture_exception
    { success: false, outcome_unknown: true, error: 'The tool did not finish answering. Verify the action before trying again.' }
  end

  def validate_tool!(approval, tool)
    raise Unavailable, 'The approval feature is disabled' unless approval.account.feature_enabled?(Captain::Hitl::GatekeeperService::FEATURE)
    raise Unavailable, 'The action tool is disabled or no longer exists' unless tool&.enabled?

    if approval.tool_definition_digest != Captain::Hitl::ToolDefinition.digest(tool)
      raise Unavailable,
            'The action tool configuration changed after the request'
    end
    raise Unavailable, 'The customer sent a newer message' if approval.newer_message_arrived?
  end

  def execute_mcp(approval, tool)
    server = Captain::McpServer.enabled_for(approval.assistant).find_by(id: tool.mcp_server_id)
    raise Unavailable, 'The MCP server is disabled or no longer exists' unless server

    Captain::Mcp::ClientService.new(server, conversation: approval.conversation).call_tool(
      tool.name, approval.effective_arguments, expected_digest: tool.approved_digest,
                                               before_call: -> { 'The customer sent a newer message' if approval.newer_message_arrived? }
    )
  end

  def execute_custom(approval, tool)
    arguments = approval.effective_arguments
    schema = public_custom_schema(tool)
    raise Unavailable, 'The reviewed arguments do not match the action tool parameters' unless JSONSchemer.schema(schema).valid?(arguments)

    conversation = approval.conversation
    state = {
      account_id: approval.account_id, assistant_id: approval.assistant_id,
      conversation: conversation.slice(:id, :display_id).symbolize_keys,
      contact: conversation.contact&.slice(:id, :email, :phone_number)&.symbolize_keys,
      contact_inbox: conversation.contact_inbox&.slice(:id, :hmac_verified)&.symbolize_keys
    }
    result = tool.tool(approval.assistant).execute_approved!(TOOL_CONTEXT.new(state), **arguments.symbolize_keys)
    { success: true, content: result.to_s.truncate(10_000) }
  end

  def public_custom_schema(tool)
    parameters = tool.param_schema.reject { |parameter| parameter['source'].present? }
    {
      'type' => 'object', 'additionalProperties' => false,
      'properties' => parameters.to_h { |parameter| [parameter.fetch('name'), { 'type' => parameter.fetch('type') }] },
      'required' => parameters.select { |parameter| parameter.fetch('required', true) }.pluck('name')
    }
  end

  def after_review(approval)
    Captain::Hitl::ApprovalEvents.broadcast(approval, Captain::Hitl::GatekeeperService::UPDATED_EVENT)
    if approval.playbook_run
      Captain::Playbooks::EngineService.new(playbook: approval.playbook_run.playbook, conversation: approval.conversation).resume_approval!(approval)
    else
      notify_customer(approval)
    end
  end

  def notify_customer(approval)
    return unless approval.status == 'executed' && approval.conversation.pending? && !approval.newer_message_arrived?

    I18n.with_locale(approval.account.locale) do
      approval.conversation.messages.create!(
        account: approval.account, inbox: approval.conversation.inbox, message_type: :outgoing, sender: approval.assistant,
        content: I18n.t('captain.hitl.executed_reply')
      )
    end
  end
end
