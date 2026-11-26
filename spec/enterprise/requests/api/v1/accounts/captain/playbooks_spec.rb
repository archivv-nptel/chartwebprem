require 'rails_helper'

RSpec.describe 'Captain playbooks', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { { api_access_token: user.access_token.token } }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/playbooks" }
  let(:graph) { { nodes: [{ id: 'reply', type: 'reply', config: { template: 'Thanks, {{customer_message}}.' } }], edges: [] } }

  before { account.enable_features!(:captain_agentic_playbooks) }

  it 'creates, publishes, and runs a playbook for an authorized conversation' do
    conversation_id = conversation.display_id
    post path, params: { playbook: { assistant_id: assistant.id, name: 'Example', graph_definition: graph } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')

    post "#{path}/#{id}/publish", headers: headers, as: :json
    expect(response.parsed_body).to include('status' => 'published')

    post "#{path}/#{id}/execute",
         params: { conversation_id: conversation_id, context: { customer_message: 'Ada' }, dry_run: false }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('status' => 'completed', 'conversation_display_id' => conversation.display_id)

    get "#{path}/#{id}/runs", headers: headers, as: :json
    expect(response.parsed_body.fetch('payload').sole).to include('status' => 'completed')
    expect(conversation.messages.outgoing.sole.content).to eq('Thanks, Ada.')
  end

  it 'does not allow agents to create playbooks or allow admins to select another account’s assistant' do
    agent = create(:user, account: account, role: :agent)
    other_assistant_id = create(:captain_assistant).id
    post path, params: { playbook: { assistant_id: assistant.id, name: 'Example', graph_definition: graph } },
               headers: { api_access_token: agent.access_token.token }, as: :json
    expect(response).to have_http_status(:forbidden)

    post path, params: { playbook: { assistant_id: other_assistant_id, name: 'Example', graph_definition: graph } },
               headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(account.captain_playbooks).to be_empty
  end
end
