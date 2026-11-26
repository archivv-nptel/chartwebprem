class Captain::Metering::ResolutionTracker
  pattr_initialize [:conversation!]

  def record(actor:, assistant: nil)
    return unless enabled? && conversation.resolved?

    resolved_at = conversation.status_changed_at
    event = conversation.account.captain_resolution_events.create_or_find_by!(conversation: conversation, resolved_at: resolved_at) do |entry|
      entry.assistant = assistant
      entry.resolution_actor = actor
      entry.episode_started_at = episode_started_at(resolved_at)
      entry.estimated_human_cost_usd = Captain::ResolutionEvent::ESTIMATED_HUMAN_COST
    end
    Captain::Metering::VerificationJob.set(wait_until: event.verification_due_at).perform_later(event.id) if event.pending?
  end

  def invalidate_reopen(resolved_at:)
    return unless enabled? && resolved_at && conversation.status_changed_at < resolved_at + Captain::ResolutionEvent::VERIFICATION_WINDOW

    event = conversation.account.captain_resolution_events.find_by(conversation: conversation, resolved_at: resolved_at)
    event&.with_lock do
      event.update!(verification_status: :invalidated_reopened, verified_at: Time.current) if event.pending?
    end
  end

  private

  def enabled?
    conversation.account.feature_enabled?(:captain_outcome_metering)
  end

  def episode_started_at(resolved_at)
    episode = ConversationOutcome.where(account_id: conversation.account_id, conversation: conversation).covering(resolved_at).chronological.last
    episode&.started_at || conversation.created_at
  end
end
