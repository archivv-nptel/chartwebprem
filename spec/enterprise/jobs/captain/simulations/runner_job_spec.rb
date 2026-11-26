require 'rails_helper'

RSpec.describe Captain::Simulations::RunnerJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:run) { account.captain_simulation_runs.create!(assistant: assistant) }
  let(:conversation) { create(:conversation, account: account, status: :resolved) }
  let(:router) { instance_double(Captain::Llm::RouterService) }

  before do
    account.enable_features!(:captain_simulations)
    allow(router).to receive(:chat)
    allow(Captain::Llm::RouterService).to receive(:new).with(account, assistant: assistant).and_return(router)
  end

  def add_messages(ticket)
    create(:message, account: account, conversation: ticket, content: 'How do I reset my password?')
    create(:message, account: account, conversation: ticket, message_type: :outgoing, content: 'Use the reset link.')
    ticket.update!(status: :resolved)
  end

  it 'scores eligible tickets once without sending messages or changing conversation status' do
    add_messages(conversation)
    create(:conversation, account: account, status: :resolved)
    create(:conversation, status: :resolved)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true, content: 'private note')
    allow(router).to receive(:chat).and_return(
      { content: 'Use the password reset link.' },
      { content: { projected_deflection: true, hallucination_score: 0.1, policy_adherence_score: 0.9, rationale: 'Accurate' }.to_json }
    )

    expect { described_class.perform_now(run.id) }.not_to(change { conversation.messages.count })
    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(
      status: 'completed', total_tickets: 2, processed_tickets: 2,
      aggregate_metrics: {
        'projected_deflection_rate' => 1.0, 'avg_hallucination_score' => 0.1, 'avg_policy_adherence' => 0.9,
        'evaluated_tickets' => 1, 'skipped_tickets' => 1
      }
    )
    expect(run.results.sole).to have_attributes(conversation: conversation, simulated_response: 'Use the password reset link.')
    expect(conversation.reload).to be_resolved
    expect(router).to have_received(:chat).twice
    expect(router).not_to have_received(:chat).with(hash_including(messages: array_including(hash_including(content: /private note/))))
  end

  it 'fails visibly when the model returns an invalid judgment' do
    add_messages(conversation)
    allow(router).to receive(:chat).and_return({ content: 'candidate' }, { content: '{"projected_deflection":"true"}' })

    expect { described_class.perform_now(run.id) }.to raise_error(Captain::Simulations::EvaluatorService::InvalidEvaluation)

    expect(run.reload).to have_attributes(status: 'failed', aggregate_metrics: { 'error' => 'evaluation_failed' })
    expect(run.results).to be_empty
  end

  it 're-enqueues the next batch if the previous job stopped at a completed batch boundary' do
    run.update!(status: :running, ticket_ids: (1..11).to_a, total_tickets: 11, processed_tickets: 10, started_at: Time.current)

    expect { described_class.perform_now(run.id, 0) }.to have_enqueued_job(described_class).with(run.id, 10)
    expect(router).not_to have_received(:chat)
  end

  it 'replays the real playbook without calling MCP or sending replies' do
    account.enable_features!(:captain_agentic_playbooks)
    add_messages(conversation)
    graph = {
      nodes: [
        { id: 'tool', type: 'mcp_tool', config: { mcp_server_id: 1, tool_name: 'update_customer' } },
        { id: 'reply', type: 'reply', config: { template: 'The update is complete.' } }
      ],
      edges: [{ source: 'tool', target: 'reply', label: 'success' }]
    }
    playbook = account.captain_playbooks.create!(assistant: assistant, name: 'Trial', graph_definition: graph)
    run.update!(playbook: playbook)
    allow(Captain::Mcp::ClientService).to receive(:new)
    allow(router).to receive(:chat).and_return(
      content: { projected_deflection: true, hallucination_score: 0.1, policy_adherence_score: 0.9, rationale: 'Accurate' }.to_json
    )

    expect { described_class.perform_now(run.id) }.not_to(change { conversation.messages.count })

    expect(Captain::Mcp::ClientService).not_to have_received(:new)
    expect(run.results.sole).to have_attributes(simulated_response: 'The update is complete.', projected_deflection: false)
    expect(playbook.runs.sole).to be_dry_run
  end

  it 'does not evaluate tickets when the feature has been disabled' do
    account.disable_features!(:captain_simulations)

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: 'failed', aggregate_metrics: { 'error' => 'feature_disabled' })
    expect(router).not_to have_received(:chat)
  end
end
