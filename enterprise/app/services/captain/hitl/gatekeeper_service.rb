class Captain::Hitl::GatekeeperService
  DEFAULT_TTL = 15.minutes
  HIGH_RISK_TOOL = /refund|cancel|credit|delete|charge|update_billing|write_crm/i
  FEATURE = 'captain_hitl_approvals'.freeze
  STATE_KEY = :captain_hitl_pending
  REQUESTED_EVENT = 'captain.hitl.approval_requested'.freeze
  UPDATED_EVENT = 'captain.hitl.approval_updated'.freeze

  def self.requires_review?(tool, read_only:)
    !read_only || HIGH_RISK_TOOL.match?(Captain::Hitl::ToolDefinition.identifier(tool))
  end

  def initialize(assistant:, conversation:, responding_to_message_id: nil, playbook_run: nil)
    @assistant = assistant
    @conversation = conversation
    @responding_to_message_id = responding_to_message_id
    @playbook_run = playbook_run
  end

  def propose!(tool:, arguments:, rationale: nil)
    ::Conversation.transaction do
      @conversation = @assistant.account.conversations.lock.find(@conversation.id)
      existing_approval || create_approval!(tool, arguments, rationale)
    end
  end

  private

  def existing_approval
    approvals = @assistant.account.captain_action_approvals.where(conversation: @conversation)
    return approvals.find_by(playbook_run: @playbook_run, status: 'pending') if @playbook_run
    return unless @responding_to_message_id

    # Captain may retry the same turn. A previous decision still owns that message.
    approvals.find_by(responding_to_message_id: @responding_to_message_id, playbook_run_id: nil)
  end

  def create_approval!(tool, arguments, rationale)
    approval = @assistant.account.captain_action_approvals.create!(
      conversation: @conversation, assistant: @assistant, playbook_run: @playbook_run,
      **tool_reference(tool),
      tool_name: Captain::Hitl::ToolDefinition.identifier(tool), tool_definition_digest: Captain::Hitl::ToolDefinition.digest(tool),
      rationale: rationale, risk_level: risk_level(arguments), proposed_arguments: arguments.deep_stringify_keys,
      responding_to_message_id: @responding_to_message_id, expires_at: DEFAULT_TTL.from_now
    )
    create_note(approval)
    ActiveRecord.after_all_transactions_commit { announce(approval) }
    approval
  end

  def announce(approval)
    Captain::Hitl::ApprovalExpiryJob.set(wait_until: approval.expires_at).perform_later(approval.id)
    Captain::Hitl::ApprovalEvents.broadcast(approval, REQUESTED_EVENT)
  end

  def tool_reference(tool)
    tool.is_a?(Captain::McpTool) ? { mcp_tool: tool } : { custom_tool: tool }
  end

  def risk_level(arguments)
    amount = arguments.with_indifferent_access[:amount]
    amount.is_a?(Numeric) && amount >= 500 ? 'critical' : 'high'
  end

  def create_note(approval)
    I18n.with_locale(@assistant.account.locale) do
      @conversation.messages.create!(
        private: true, account: @assistant.account, inbox: @conversation.inbox, message_type: :outgoing, sender: @assistant,
        content: I18n.t('captain.hitl.requested_note', id: approval.id, tool: approval.tool_name)
      )
    end
  end
end
