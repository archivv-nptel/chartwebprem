require 'rails_helper'

RSpec.describe Captain::Llm::ProviderContext do
  let(:account) { create(:account) }
  let(:router) { Captain::Llm::RouterService.new(account) }
  let(:response_headers) { { 'Content-Type' => 'application/json' } }
  let(:encryption_key) { ActiveRecord::Encryption::Key.new(SecureRandom.random_bytes(32)) }

  around do |example|
    key_provider = ActiveRecord::Encryption::KeyProvider.new([encryption_key])
    ActiveRecord::Encryption.with_encryption_context(key_provider: key_provider) { example.run }
  end

  before do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    allow(SsrfFilter::DEFAULT_RESOLVER).to receive(:call).and_return([IPAddr.new('93.184.215.14')])
  end

  it 'calls an Azure OpenAI deployment using the saved resource URL and key' do
    provider = account.captain_llm_provider_configs.create!(
      name: 'Azure', provider_type: 'azure_openai', model_id: 'tenant-deployment', endpoint_url: 'https://tenant.openai.azure.com',
      credentials: { 'api_key' => 'azure-test-key' }
    )
    response = { model: 'deployment-model', choices: [{ message: { role: 'assistant', content: 'OK' }, finish_reason: 'stop' }] }
    request = stub_request(:post, 'https://tenant.openai.azure.com/openai/v1/chat/completions')
              .with(headers: { 'api-key' => 'azure-test-key' })
              .to_return(body: response.to_json, headers: response_headers)

    expect(router.test_connection(provider)).to include(content: 'OK')
    expect(request).to have_been_requested
  end

  it 'signs a request to the configured Bedrock region and model' do
    provider = account.captain_llm_provider_configs.create!(
      name: 'Bedrock', provider_type: 'aws_bedrock', model_id: 'amazon.nova-lite-v1:0', region: 'us-east-1',
      credentials: { 'aws_access_key_id' => 'test-access-id', 'aws_secret_access_key' => 'test-signing-key' }
    )
    endpoint = 'https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.nova-lite-v1:0/converse'
    response = { output: { message: { content: [{ text: 'OK' }] } }, stopReason: 'end_turn' }
    request = stub_request(:post, endpoint)
              .with(headers: { 'Authorization' => %r{AWS4-HMAC-SHA256 Credential=test-access-id/} })
              .to_return(body: response.to_json, headers: response_headers)

    expect(router.test_connection(provider)).to include(content: 'OK')
    expect(request).to have_been_requested
  end

  it 'authenticates a Vertex service account and uses the configured project and region' do
    service_account_key = { 'client_email' => 'captain-test@captain-test.iam.gserviceaccount.com',
                            'private_key' => OpenSSL::PKey::RSA.generate(2048).to_pem }
    provider = account.captain_llm_provider_configs.create!(
      name: 'Vertex', provider_type: 'google_vertex', model_id: 'gemini-2.5-flash', region: 'us-central1',
      credentials: { 'project_id' => 'captain-test', 'service_account_key' => service_account_key }
    )
    token = { access_token: 'vertex-test-token', expires_in: 3600, token_type: 'Bearer' }
    auth = stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token').to_return(body: token.to_json, headers: response_headers)
    endpoint = 'https://us-central1-aiplatform.googleapis.com/v1beta1/projects/captain-test/locations/us-central1/publishers/google/models/' \
               'gemini-2.5-flash:generateContent'
    response = { candidates: [{ content: { role: 'model', parts: [{ text: 'OK' }] }, finishReason: 'STOP' }] }
    request = stub_request(:post, endpoint).with(headers: { 'Authorization' => 'Bearer vertex-test-token' })
                                           .to_return(body: response.to_json, headers: response_headers)

    expect(router.test_connection(provider)).to include(content: 'OK')
    expect(auth).to have_been_requested
    expect(request).to have_been_requested
  end
end
