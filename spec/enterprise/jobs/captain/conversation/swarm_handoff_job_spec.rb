require 'rails_helper'

RSpec.describe 'Captain specialist routing in the response job', type: :job do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, swarm_role: 'generalist') }
  let!(:billing) { create(:captain_assistant, account: account, swarm_role: 'billing') }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:customer_message) { create(:message, conversation: conversation, content: 'Please send my invoice', message_type: :incoming) }
  let(:router) { instance_double(Captain::Llm::RouterService) }

  before do
    account.enable_features!(:captain_swarm_handoffs)
    allow(Captain::Llm::RouterService).to receive(:new).and_return(router)
  end

  it 'delivers the response from the selected specialist through the ordinary conversation workflow' do
    allow(router).to receive(:chat).and_return(
      { content: { action: 'delegate', target_role: 'billing', summary: 'Invoice request' }.to_json },
      { content: { action: 'respond' }.to_json }
    )
    runner = instance_double(Captain::Assistant::AgentRunnerService, last_run_result: nil, response_discarded?: false, handoff_completed?: false,
                                                                     generate_response: { 'response' => 'I can help with billing.' })
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)

    Captain::Conversation::ResponseBuilderJob.perform_now(conversation.reload, assistant, customer_message.id)

    expect(conversation.messages.outgoing.last).to have_attributes(sender: billing, content: 'I can help with billing.')
    expect(account.captain_swarm_handoffs.last).to have_attributes(conversation: conversation, to_assistant: billing)
  end

  it 'uses the existing human handoff and stores the brief privately' do
    allow(router).to receive(:chat).and_return(
      { content: { action: 'escalate_human', summary: 'Invoice discrepancy' }.to_json },
      { content: 'Check invoice totals.' }
    )

    Captain::Conversation::ResponseBuilderJob.perform_now(conversation.reload, assistant, customer_message.id)

    expect(conversation.reload).to be_open
    expect(conversation.messages.where(private: true).last.content).to include('Check invoice totals.')
    expect(conversation.messages.outgoing.where(private: false).last.content).not_to include('Check invoice totals.')
    expect(account.captain_swarm_handoffs.last).to have_attributes(conversation: conversation, handoff_type: 'agent_to_human')
  end
end
