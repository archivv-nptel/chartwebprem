class Captain::Metering::VerificationJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Captain::ResolutionEvent.find_by(id: event_id)
    return unless event&.account&.feature_enabled?(:captain_outcome_metering)

    return reschedule(event) if event.pending? && event.verification_due_at.future?

    verify(event)
    enqueue_meter_event(event)
  end

  private

  def reschedule(event)
    self.class.set(wait_until: event.verification_due_at).perform_later(event.id)
  end

  def enqueue_meter_event(event)
    return unless event.captain_ai? && event.verified? && event.stripe_meter_event_id.blank?

    Captain::Metering::StripeMeterJob.perform_later(event.id)
  end

  def verify(event)
    event.conversation.with_lock do
      event.reload
      next unless event.pending?

      status = verification_status(event)
      fee = Captain::ResolutionEvent::OUTCOME_FEE if status == :verified && event.captain_ai?
      event.update!(verification_status: status, verified_at: Time.current, csat_rating: csat_rating(event), billable_fee_usd: fee || 0)
    end
  end

  def verification_status(event)
    changed_at = event.conversation.status_changed_at
    return :invalidated_reopened if changed_at != event.resolved_at && changed_at <= event.verification_due_at
    return :invalidated_human_takeover if event.captain_ai? && human_takeover?(event)

    :verified
  end

  def human_takeover?(event)
    event.conversation.messages.outgoing.exists?(
      private: false, sender_type: 'User', created_at: event.episode_started_at..event.verification_due_at
    )
  end

  def csat_rating(event)
    event.account.csat_survey_responses.joins(:message).where(conversation: event.conversation)
         .where(messages: { created_at: event.resolved_at..event.verification_due_at })
         .order(created_at: :desc, id: :desc).pick(:rating)
  end
end
