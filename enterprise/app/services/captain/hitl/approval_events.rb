module Captain::Hitl::ApprovalEvents
  def self.broadcast(approval, event)
    conversation = approval.conversation
    account = approval.account
    tokens = reviewer_tokens(account, conversation)
    data = { id: approval.id, account_id: account.id, conversation_display_id: conversation.display_id }
    ActionCableBroadcastJob.perform_later(tokens, event, data) if tokens.any?
  end

  def self.reviewer_tokens(account, conversation)
    # Notify the assigned agent and the account supervisors. Recheck access before broadcasting.
    administrators = account.account_users.where(role: :administrator)
    memberships = administrators.or(account.account_users.where(user_id: conversation.assignee_id))
    memberships.includes(:user, :custom_role).filter_map do |membership|
      context = { user: membership.user, account: account, account_user: membership }
      membership.user.pubsub_token if ConversationPolicy.new(context, conversation).show?
    end
  end
  private_class_method :reviewer_tokens
end
