require 'rails_helper'

RSpec.describe Captain::Metering::StripeMeterJob do
  let(:account) { create(:account, custom_attributes: { 'stripe_customer_id' => 'cus_test_captain' }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:event) do
    account.captain_resolution_events.create!(
      conversation: conversation, episode_started_at: 3.days.ago, resolved_at: 2.days.ago, verified_at: 1.day.ago,
      resolution_actor: :captain_ai, verification_status: :verified
    )
  end

  before { account.enable_features!(:captain_outcome_metering) }

  it 'sends a stable billing identifier and skips a recorded meter event on retry' do
    identifier = "chatwoot-captain-#{conversation.uuid}-#{event.id}"
    meter = instance_double(Stripe::Billing::MeterEvent, identifier: identifier)
    allow(Stripe).to receive(:api_key).and_return('test-key')
    allow(Stripe::Billing::MeterEvent).to receive(:create).and_return(meter)

    with_modified_env(CAPTAIN_STRIPE_METER_EVENT_NAME: 'captain_verified_resolution') do
      2.times { described_class.perform_now(event.id) }
    end

    expect(Stripe::Billing::MeterEvent).to have_received(:create).with(
      hash_including(identifier: identifier, payload: { stripe_customer_id: 'cus_test_captain', value: '1' }),
      { idempotency_key: identifier }
    ).once
    expect(event.reload.stripe_meter_event_id).to eq(identifier)
  end
end
