require 'rails_helper'

RSpec.describe Captain::Metering::VerificationJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  before { account.enable_features!(:captain_outcome_metering) }

  def resolve_with_captain
    conversation.resolved!
    Captain::ConversationEvents.resolved(conversation: conversation, assistant: assistant, source: 'tool', at: Time.current)
    account.captain_resolution_events.sole
  end

  it 'records only an explicitly attributed Captain resolution and verifies it after the waiting window' do
    expect { conversation.resolved! }.not_to change(Captain::ResolutionEvent, :count)
    conversation.open!

    event = resolve_with_captain
    described_class.perform_now(event.id)
    expect(event.reload).to be_pending

    travel 25.hours do
      expect { described_class.perform_now(event.id) }.to have_enqueued_job(Captain::Metering::StripeMeterJob).with(event.id)
      expect(event.reload).to have_attributes(verification_status: 'verified', assistant: assistant, billable_fee_usd: BigDecimal('0.70'))
    end
  end

  it 'disqualifies a resolution if the conversation reopens and resolves again during the window' do
    event = resolve_with_captain
    travel 1.hour do
      conversation.open!
      conversation.resolved!
    end

    travel 25.hours do
      expect { described_class.perform_now(event.id) }.not_to have_enqueued_job(Captain::Metering::StripeMeterJob)
      expect(event.reload).to be_invalidated_reopened
    end
  end

  it 'does not bill resolutions with a public human reply in the episode' do
    agent = create(:user, account: account, role: :agent)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing, sender: agent)
    event = resolve_with_captain

    travel 25.hours do
      described_class.perform_now(event.id)
      expect(event.reload).to have_attributes(verification_status: 'invalidated_human_takeover', billable_fee_usd: 0)
    end
  end
end
