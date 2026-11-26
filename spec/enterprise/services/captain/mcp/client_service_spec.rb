require 'rails_helper'

RSpec.describe Captain::Mcp::ClientService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { 'https://mcp.example.com/mcp' }
  let(:fake) { FakeMcpServer.new }
  let(:server) { Captain::McpServer.create!(account: account, assistant: assistant, name: 'Orders', url: url) }
  let(:client) { described_class.new(server, conversation: conversation) }
  let(:definition) do
    {
      name: 'lookup', description: 'Look up an order',
      inputSchema: { type: 'object', properties: { reference: { type: 'string' } }, required: ['reference'] },
      annotations: { readOnlyHint: true }
    }
  end

  before do
    account.enable_features!(Captain::McpServer::FEATURE_FLAG)
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.216.34')])
    stub_request(:any, url).to_rack(fake)
  end

  def approve(tool, fields = {})
    fake.tools = [tool]
    definitions = Captain::Mcp::Connection.new(server).tool_definitions.index_by { |entry| entry['name'] }
    server.sync_tools({ 'lookup' => fields }, definitions)
    server.tools.sole
  end

  def tool_calls
    a_request(:post, url).with { |request| JSON.parse(request.body)['method'] == 'tools/call' }
  end

  it 'calls the live approved tool with values supplied by Chatwoot' do
    approve(definition, 'param_sources' => { 'reference' => { 'source' => 'fixed', 'value' => 'chatwoot-value' } })

    expect(client.call_tool('lookup', { reference: 'replacement' })).to eq(success: true, content: 'Called lookup')

    expect(a_request(:post, url).with do |request|
      JSON.parse(request.body).dig('params', 'arguments', 'reference') == 'chatwoot-value'
    end).to have_been_made.once
  end

  it 'does not execute if the stored approval differs from the server definition' do
    approve(definition)
    fake.tools = [definition.merge(description: 'A different operation')]

    expect(client.call_tool('lookup', { reference: 'order-1' })).to include(success: false, outcome_unknown: false)
    expect(tool_calls).not_to have_been_made
    expect(server.tools.sole).to be_review_changed
  end

  it 'requires the approved digest for a tool that can change data' do
    tool = approve(definition.merge(annotations: { readOnlyHint: false }))

    expect(client.call_tool('lookup', { reference: 'order-1' })).to include(success: false)
    expect(client.call_tool('lookup', { reference: 'order-1' }, expected_digest: 'stale')).to include(success: false)
    expect(tool_calls).not_to have_been_made

    expect(client.call_tool('lookup', { reference: 'order-1' }, expected_digest: tool.approved_digest)).to include(success: true)
    expect(tool_calls).to have_been_made.once
  end

  it 'rejects input that fails the approved schema and cross-account conversations' do
    approve(definition)

    expect(client.call_tool('lookup', { reference: 123 })).to include(success: false)
    expect(described_class.new(server, conversation: create(:conversation)).call_tool('lookup', { reference: 'order-1' })).to include(success: false)
    expect(tool_calls).not_to have_been_made
  end

  it 'does not call the server when an admin changes a parameter source during discovery' do
    tool = approve(definition)
    changing_server = lambda do |env|
      body = env.fetch('rack.input')
      message = JSON.parse(body.read)
      body.rewind
      tool.update!(param_sources: { 'reference' => { 'source' => 'fixed', 'value' => 'new-value' } }) if message['method'] == 'tools/list'
      fake.call(env)
    end
    stub_request(:any, url).to_rack(changing_server)

    expect(client.call_tool('lookup', { reference: 'order-1' })).to include(success: false, outcome_unknown: false)
    expect(tool_calls).not_to have_been_made
  end

  it 'reports an uncertain outcome when a mutating call gets an unusable response' do
    tool = approve(definition.merge(annotations: { readOnlyHint: false }))
    stub_request(:post, url).with { |request| JSON.parse(request.body)['method'] == 'tools/call' }.to_return(status: 500, body: '{}')

    result = client.call_tool('lookup', { reference: 'order-1' }, expected_digest: tool.approved_digest)

    expect(result).to include(success: false, outcome_unknown: true)
    expect(tool_calls).to have_been_made.once
  end
end
