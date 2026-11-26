require 'rails_helper'

RSpec.describe Captain::Playbooks::EngineService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:playbook) { account.captain_playbooks.create!(assistant: assistant, name: 'Order help', graph_definition: definition) }
  let(:definition) do
    {
      nodes: [
        { id: 'start', type: 'condition', config: { field: 'refund.amount', operator: 'lte', value: 100 } },
        { id: 'yes', type: 'reply', config: { template: 'Checking {{refund.amount}}.' } },
        { id: 'no', type: 'reply', config: { template: 'I need to review this amount.' } }
      ],
      edges: [{ source: 'start', target: 'yes', label: 'true' }, { source: 'start', target: 'no', label: 'false' }]
    }
  end

  before { account.enable_features!(:captain_agentic_playbooks) }

  it 'walks the matching deterministic branch and records the reply' do
    playbook.publish!
    run = described_class.new(playbook: playbook, conversation: conversation).execute!(initial_context: { refund: { amount: 25 } })

    expect(run).to be_completed
    expect(run.execution_trace.pluck('node_id')).to eq(%w[start yes])
    expect(conversation.messages.last.content).to eq('Checking 25.')
  end

  it 'does not coerce missing values into a passing number and does not send dry-run messages' do
    expect do
      run = described_class.new(playbook: playbook, conversation: conversation, dry_run: true).execute!
      expect(run).to be_completed
      expect(run.context_state['last_reply']).to eq('I need to review this amount.')
    end.not_to(change { conversation.messages.count })
  end

  it 'does not repeat a live playbook for the same trigger message' do
    playbook.publish!
    message = create(:message, :incoming, account: account, inbox: conversation.inbox, conversation: conversation)
    engine = described_class.new(playbook: playbook, conversation: conversation)
    first = engine.execute!(trigger_message: message)
    second = engine.execute!(trigger_message: message)

    expect(first.id).to eq(second.id)
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'rejects cyclic and invalid graphs and conditions without both branches at publication' do
    expect { playbook.update!(graph_definition: definition.merge(edges: [{ source: 'start', target: 'start', label: 'true' }])) }
      .to raise_error(ActiveRecord::RecordInvalid)

    playbook.reload
    expect { playbook.update!(status: :published, graph_definition: { nodes: [definition[:nodes].first], edges: [] }) }
      .to raise_error(ActiveRecord::RecordInvalid, /true and false branches/)
  end
end
