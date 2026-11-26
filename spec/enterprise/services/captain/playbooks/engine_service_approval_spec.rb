require 'rails_helper'

RSpec.describe Captain::Playbooks::EngineService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:reviewer) { create(:user, account: account, role: :administrator) }
  let(:url) { 'https://mcp.example.com/mcp' }
  let(:fake) { FakeMcpServer.new }
  let(:server) { Captain::McpServer.create!(account: account, assistant: assistant, name: 'Orders', url: url) }
  let(:playbook) { account.captain_playbooks.create!(assistant: assistant, name: 'Order help', graph_definition: graph) }
  let(:graph) do
    {
      nodes: [
        {
          id: 'note', type: 'mcp_tool',
          config: { mcp_server_id: server.id, tool_name: 'annotate_order', arguments: { note: '{{customer_message}}' } }
        },
        { id: 'success', type: 'reply', config: { template: 'Your update is complete.' } },
        { id: 'rejected', type: 'reply', config: { template: 'The requested update was declined.' } }
      ],
      edges: [{ source: 'note', target: 'success', label: 'success' }, { source: 'note', target: 'rejected', label: 'rejected' }]
    }
  end

  before do
    account.enable_features!(:captain_agentic_playbooks, :captain_hitl_approvals, :captain_mcp_servers)
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.216.34')])
    stub_request(:any, url).to_rack(fake)
    fake.tools = [
      {
        name: 'annotate_order', description: 'Add a customer note',
        inputSchema: { type: 'object', properties: { note: { type: 'string' } }, required: ['note'] },
        annotations: { readOnlyHint: false }
      }
    ]
    definitions = Captain::Mcp::Connection.new(server).tool_definitions.index_by { |entry| entry['name'] }
    server.sync_tools({ 'annotate_order' => {} }, definitions)
    playbook.publish!
  end

  def tool_calls
    a_request(:post, url).with { |request| JSON.parse(request.body)['method'] == 'tools/call' }
  end

  it 'executes the human-reviewed write and continues the snapshotted playbook once' do
    run = described_class.new(playbook: playbook, conversation: conversation).execute!(initial_context: { customer_message: 'Ring the doorbell' })
    expect(run).to be_waiting_hitl
    expect(tool_calls).not_to have_been_made
    approval = run.action_approvals.sole

    Captain::Hitl::ActionExecutorService.new.approve_and_execute!(approval: approval, reviewer: reviewer)

    expect(tool_calls).to have_been_made.once
    expect(run.reload).to be_completed
    expect(run.execution_trace.pluck('outcome')).to eq(%w[pending_approval success default])
    expect(conversation.messages.outgoing.last.content).to eq('Your update is complete.')
  end

  it 'follows the rejected branch without sending a tool call' do
    run = described_class.new(playbook: playbook, conversation: conversation).execute!
    Captain::Hitl::ActionExecutorService.new.reject!(approval: run.action_approvals.sole, reviewer: reviewer, reason: 'Wrong order')

    expect(tool_calls).not_to have_been_made
    expect(run.reload).to be_completed
    expect(conversation.messages.outgoing.last.content).to eq('The requested update was declined.')
  end

  it 'simulates the MCP result and public reply without an approval, tool call or message' do
    run = described_class.new(playbook: playbook, conversation: conversation, dry_run: true).execute!

    expect(run).to be_completed
    expect(run.context_state['last_reply']).to eq('Your update is complete.')
    expect(run.action_approvals).to be_empty
    expect(conversation.messages).to be_empty
    expect(tool_calls).not_to have_been_made
  end
end
