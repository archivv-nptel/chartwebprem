module Captain::Hitl::PublicToolGate
  class ApprovalRequired < StandardError; end

  private

  def request_mutation_approval(tool, tool_context, params)
    return unless @assistant.account.feature_enabled?(Captain::Hitl::GatekeeperService::FEATURE)
    return unless Captain::Hitl::GatekeeperService.requires_review?(tool, read_only: read_only?)

    conversation = find_conversation(tool_context.state)
    return unless conversation

    # Resolve managed arguments now so a tool that needs a verified customer never proposes an unverified action.
    arguments_for(tool_context, params)
    gate = Captain::Hitl::GatekeeperService.new(
      assistant: @assistant, conversation: conversation, responding_to_message_id: tool_context.state[:responding_to_message_id]
    )
    approval = gate.propose!(tool: tool, arguments: params)
    tool_context.state[Captain::Hitl::GatekeeperService::STATE_KEY] = approval.previously_new_record? ? :requested : :already_requested
    raise ApprovalRequired, 'This action is awaiting a support agent’s approval.'
  end
end
