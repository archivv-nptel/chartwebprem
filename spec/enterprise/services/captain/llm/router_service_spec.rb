require 'rails_helper'

RSpec.describe Captain::Llm::RouterService do
  let(:account) { create(:account) }
  let(:router) { described_class.new(account) }
  let(:messages) { [{ role: 'user', content: 'Help with my ticket' }] }
  let(:primary_url) { 'https://primary.example.com/v1/chat/completions' }
  let(:backup_url) { 'https://backup.example.com/v1/chat/completions' }
  let(:remote_response) do
    {
      model: 'custom-model',
      choices: [{ message: { role: 'assistant', content: 'How can I help?' }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 5, completion_tokens: 6, total_tokens: 11 }
    }.to_json
  end

  before do
    account.enable_features!(:captain_byom_routing)
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.215.14')])
  end

  def provider(endpoint, **attributes)
    account.captain_llm_provider_configs.create!(
      name: endpoint, provider_type: 'openai_compatible', endpoint_url: "https://#{endpoint}.example.com/v1",
      model_id: 'custom-model', **attributes
    )
  end

  it 'sends the request to the configured endpoint and reports its completion' do
    provider('primary')
    request = stub_request(:post, primary_url).with(body: hash_including(model: 'custom-model', messages: messages.map(&:stringify_keys)))
                                              .to_return(body: remote_response, headers: { 'Content-Type' => 'application/json' })

    result = router.chat(messages: messages)

    expect(request).to have_been_requested
    expect(result).to eq(content: 'How can I help?', model: 'custom-model', tool_calls: [], usage: { prompt_tokens: 5, completion_tokens: 6 })
  end

  it 'fails over to another approved endpoint' do
    provider('primary', zero_data_retention: true)
    provider('backup', priority: 2, zero_data_retention: true)
    stub_request(:post, primary_url).to_return(status: 503)
    request = stub_request(:post, backup_url).to_return(body: remote_response, headers: { 'Content-Type' => 'application/json' })

    expect(router.chat(messages: messages)[:content]).to eq('How can I help?')
    expect(request).to have_been_requested
  end

  it 'keeps a ZDR-pinned assistant on a ZDR route even when its primary is disabled' do
    pinned = provider('primary', enabled: false, zero_data_retention: true)
    provider('backup')
    assistant = create(:captain_assistant, account: account, llm_provider_config: pinned)
    routed = described_class.new(account, assistant: assistant)

    expect { routed.chat(messages: messages) }.to raise_error(Captain::Llm::ProviderChain::Unavailable)
    expect(WebMock).not_to have_requested(:post, backup_url)
  end

  it 'rejects an endpoint resolving to a loopback address before connecting' do
    provider('primary')
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('127.0.0.1')])

    expect { router.chat(messages: messages) }.to raise_error(Captain::Llm::ProviderChain::Unavailable)
    expect(WebMock).not_to have_requested(:post, primary_url)
  end

  it 'matches the route task and does not choose a different model after a model was selected' do
    provider('primary', routing_rules: { task: 'editor' })
    provider('backup')

    expect { router.chat(messages: messages, model_override: 'unconfigured-model') }.to raise_error(Captain::Llm::ProviderChain::Unavailable)
    expect(WebMock).not_to have_requested(:post, primary_url)
    expect(WebMock).not_to have_requested(:post, backup_url)
  end
end
