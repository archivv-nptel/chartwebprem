class Captain::Metering::StripeMeterJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Captain::ResolutionEvent.find_by(id: event_id)
    return unless eligible?(event)

    identifier = "chatwoot-captain-#{event.conversation.uuid}-#{event.id}"
    meter = Stripe::Billing::MeterEvent.create(
      {
        event_name: ENV.fetch('CAPTAIN_STRIPE_METER_EVENT_NAME'), identifier: identifier,
        timestamp: event.verified_at.to_i,
        payload: { stripe_customer_id: event.account.custom_attributes.fetch('stripe_customer_id'), value: '1' }
      },
      { idempotency_key: identifier }
    )
    event.update!(stripe_meter_event_id: meter.identifier)
  end

  private

  def eligible?(event)
    return false unless event&.captain_ai? && event.verified? && event.stripe_meter_event_id.blank?

    meter_configured?(event.account) && event.account.feature_enabled?(:captain_outcome_metering)
  end

  def meter_configured?(account)
    Stripe.api_key.present? && ENV['CAPTAIN_STRIPE_METER_EVENT_NAME'].present? && account.custom_attributes['stripe_customer_id'].present?
  end
end
