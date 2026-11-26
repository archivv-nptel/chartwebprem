require 'rails_helper'

RSpec.describe Captain::Llm::RoutedAgentRunner do
  let(:assistant) { create(:captain_assistant) }
  let(:agent) { Agents::Agent.new(name: 'captain', instructions: 'You provide support') }
  let(:runner) { described_class.new([agent], assistant: assistant) }
  let(:endpoint) { 'https://provider.example.com/v1/chat/completions' }
  let(:provider_response) do
    {
      model: 'assistant-model',
      choices: [{ message: { role: 'assistant', content: 'My reply' }, finish_reason: 'stop' }]
    }.to_json
  end

  before do
    assistant.account.captain_llm_provider_configs.create!(name: 'External', provider_type: 'openai_compatible',
                                                           model_id: 'assistant-model', endpoint_url: 'https://provider.example.com/v1')
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.215.14')])
  end

  it 'preserves the normal runner instructions and uses the scoped external model' do
    request = stub_request(:post, endpoint)
              .with(body: hash_including('model' => 'assistant-model',
                                         'messages' => [{ 'role' => 'developer', 'content' => 'You provide support' },
                                                        { 'role' => 'user', 'content' => 'I need help' }]))
              .to_return(body: provider_response, headers: { 'Content-Type' => 'application/json' })

    result = runner.run('I need help')

    expect(result.error).to be_nil
    expect(result.output).to eq('My reply')
    expect(request).to have_been_requested
  end

  it 'does not replay a turn when an external model fails after a tool executes' do
    tool = Captain::Tools::FaqLookupTool.new(assistant)
    specialist = Agents::Agent.new(name: 'captain', instructions: 'Look up information', tools: [tool])
    routed = described_class.new([specialist], assistant: assistant)
    assistant.account.captain_llm_provider_configs.create!(
      name: 'Backup', provider_type: 'openai_compatible', model_id: 'backup-model', priority: 2, endpoint_url: 'https://backup.example.com/v1'
    )
    tool_response = {
      model: 'assistant-model',
      choices: [{ message: { role: 'assistant', tool_calls: [
        { id: 'tool-call-1', type: 'function', function: { name: tool.name, arguments: '{"query":"invoices"}' } }
      ] }, finish_reason: 'tool_calls' }]
    }
    stub_request(:post, endpoint)
      .to_return({ body: tool_response.to_json, headers: { 'Content-Type' => 'application/json' } }, { status: 503 })
    backup_request = stub_request(:post, 'https://backup.example.com/v1/chat/completions')
    expect(tool).to receive(:execute).once.and_return('FAQ result')

    expect { routed.run('I need help') }.to raise_error(Captain::Llm::ProviderChain::Unavailable, /after tool execution/)
    expect(backup_request).not_to have_been_requested
  end
end
