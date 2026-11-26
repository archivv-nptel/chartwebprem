module Captain::Conversation::ApprovalGates
  private

  def existing_approval_for_turn?
    return false unless @responding_to_message_id && account.feature_enabled?(Captain::Hitl::GatekeeperService::FEATURE)

    account.captain_action_approvals.exists?(
      conversation: @conversation, responding_to_message_id: @responding_to_message_id, playbook_run_id: nil
    )
  end

  def approval_pending?
    account.feature_enabled?(Captain::Hitl::GatekeeperService::FEATURE) &&
      @run_result&.context&.dig(:state, Captain::Hitl::GatekeeperService::STATE_KEY)
  end

  def process_approval_response
    return unless approval_pending? == :requested && conversation_pending? && !newer_customer_message_arrived?

    I18n.with_locale(account.locale) do
      @response = { 'response' => I18n.t('captain.hitl.waiting_reply') }
      process_standard_response
    end
  end
end
