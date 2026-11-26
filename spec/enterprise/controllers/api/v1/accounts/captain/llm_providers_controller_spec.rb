require 'rails_helper'

RSpec.describe 'Captain model provider management', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/llm_providers" }
  let(:attributes) do
    {
      name: 'Tenant provider', provider_type: 'openai_compatible', endpoint_url: 'https://provider.example.com/v1', model_id: 'tenant-model'
    }
  end

  before { account.enable_features!(:captain_byom_routing) }

  it 'requires an administrator for provider configuration' do
    post path, params: { llm_provider: attributes }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(account.captain_llm_provider_configs).to be_empty
  end

  it 'encrypts provider credentials and never includes them in the API representation' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    key = ActiveRecord::Encryption::Key.new(SecureRandom.random_bytes(32))
    key_provider = ActiveRecord::Encryption::KeyProvider.new([key])
    secret = 'tenant-api-key'

    ActiveRecord::Encryption.with_encryption_context(key_provider: key_provider) do
      post path, params: { llm_provider: attributes.merge(credentials: { api_key: secret }) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.body).not_to include(secret, 'encrypted_credentials')
      expect(response.parsed_body['credentials_configured']).to be(true)
      record = account.captain_llm_provider_configs.find(response.parsed_body.fetch('id'))
      expect(record.encrypted_credentials_before_type_cast).not_to include(secret)
      expect(record.credentials).to eq('api_key' => secret)
    end
  end

  it 'returns other tenants’ provider IDs as missing' do
    other_provider = create(:account).captain_llm_provider_configs.create!(attributes)
    patch "#{path}/#{other_provider.id}", params: { llm_provider: { enabled: false } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(other_provider.reload.enabled?).to be(true)
  end

  it 'forbids configuring a model provider feature when it is disabled' do
    account.disable_features!(:captain_byom_routing)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
