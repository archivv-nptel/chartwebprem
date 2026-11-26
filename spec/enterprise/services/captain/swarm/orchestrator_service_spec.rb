require 'rails_helper'

RSpec.describe Captain::Swarm::OrchestratorService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:assistant) { create(:captain_assistant, account: account, swarm_role: 'generalist') }
  let!(:billing) { create(:captain_assistant, account: account, swarm_role: 'billing', swarm_capabilities: ['Invoices']) }
  let(:router) { instance_double(Captain::Llm::RouterService) }
  let(:service) { described_class.new(conversation: conversation, assistant: assistant) }
  let(:history) { [{ role: 'user', content: 'I need my invoice' }] }

  before do
    allow(Captain::Llm::RouterService).to receive(:new).and_return(router)
  end

  it 'returns the selected assistant and records a structured handoff' do
    allow(router).to receive(:chat).and_return(
      { content: { action: 'delegate', target_role: 'billing', summary: 'Invoice request' }.to_json },
      { content: { action: 'respond' }.to_json }
    )

    route = service.route(message_history: history)

    expect(route.assistant).to eq(billing)
    expect { service.persist!(route) }.to change(Captain::SwarmHandoff, :count).by(1)
    handoff = account.captain_swarm_handoffs.last
    expect(handoff).to have_attributes(from_assistant: assistant, to_assistant: billing, handoff_type: 'agent_to_agent',
                                       structured_context: { 'summary' => 'Invoice request' })
  end

  it 'breaks a repeated specialist route and records a private escalation brief' do
    allow(router).to receive(:chat).and_return(
      { content: { action: 'delegate', target_role: 'billing' }.to_json },
      { content: { action: 'delegate', target_role: 'billing' }.to_json },
      { content: 'Review the customer’s missing invoice.' }
    )

    route = service.route(message_history: history)
    service.persist!(route)

    expect(route.assistant).to be_nil
    expect(account.captain_swarm_handoffs.last).to have_attributes(handoff_type: 'agent_to_human', hop_count: 2)
    expect(conversation.messages.last).to have_attributes(private: true, content: include('missing invoice'))
  end

  it 'does not send a message to a guessed role from the model' do
    create(:captain_assistant, swarm_role: 'shipping')
    allow(router).to receive(:chat).and_return(
      { content: { action: 'delegate', target_role: 'shipping' }.to_json },
      { content: 'Review the order.' }
    )

    route = service.route(message_history: history)

    expect(route.assistant).to be_nil
    expect(route.handoffs.first).to include(handoff_type: 'agent_to_human', to_assistant: nil)
  end
end
