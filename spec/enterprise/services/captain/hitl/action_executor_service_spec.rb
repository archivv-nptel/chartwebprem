require 'rails_helper'

RSpec.describe Captain::Hitl::ActionExecutorService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:reviewer) { create(:user, account: account, role: :administrator) }
  let(:custom_tool) { create(:captain_custom_tool, :with_post, account: account, assistant: assistant) }
  let(:trigger) { create(:message, :incoming, account: account, conversation: conversation, inbox: conversation.inbox) }
  let(:state) { { conversation: { id: conversation.id }, responding_to_message_id: trigger.id } }
  let(:context) { Struct.new(:state).new(state) }
  let(:endpoint_request) { stub_request(:post, custom_tool.endpoint_url).to_return(status: 200, body: '{"written":true}') }

  before do
    account.enable_features!(:captain_hitl_approvals)
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.216.34')])
    endpoint_request
  end

  def request_approval
    expect { custom_tool.tool(assistant).perform(context) }.to raise_error(Captain::Hitl::PublicToolGate::ApprovalRequired)
    account.captain_action_approvals.sole
  end

  it 'pauses the customer tool and executes it once after a human approves it' do
    approval = request_approval
    expect(endpoint_request).not_to have_been_requested
    expect(state).to include(captain_hitl_pending: :requested)

    described_class.new.approve_and_execute!(approval: approval, reviewer: reviewer)
    expect(approval.reload.status).to eq('executed')
    expect(conversation.messages.outgoing.where(private: false).last.content).to eq('Your request has been approved and completed.')

    expect do
      described_class.new.approve_and_execute!(approval: approval, reviewer: reviewer)
    end.to raise_error(described_class::Unavailable)
    expect(endpoint_request).to have_been_requested.once
  end

  it 'rejects cross-account reviewers and preserves the existing pending request' do
    approval = request_approval
    different_account = create(:user)

    expect { described_class.new.approve_and_execute!(approval: approval, reviewer: different_account) }.to raise_error(Pundit::NotAuthorizedError)

    expect(approval.reload.status).to eq('pending')
    expect(endpoint_request).not_to have_been_requested
  end

  it 'does not execute an expired request or a changed tool' do
    approval = request_approval
    travel_to(approval.expires_at + 1.second) do
      expect { described_class.new.approve_and_execute!(approval: approval, reviewer: reviewer) }.to raise_error(described_class::Unavailable)
    end

    custom_tool.update!(request_template: '{"other": "intent"}')
    described_class.new.approve_and_execute!(approval: approval, reviewer: reviewer)

    expect(approval.reload.status).to eq('failed')
    expect(endpoint_request).not_to have_been_requested
  end
end
