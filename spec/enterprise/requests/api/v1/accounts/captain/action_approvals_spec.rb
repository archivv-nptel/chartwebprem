require 'rails_helper'

RSpec.describe 'Captain action approvals', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:tool) { create(:captain_custom_tool, :with_post, account: account, assistant: assistant) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/action_approvals" }

  before { account.enable_features!(:captain_hitl_approvals) }

  it 'does not expose an approval to an agent without conversation access' do
    approval = Captain::Hitl::GatekeeperService.new(assistant: assistant, conversation: conversation).propose!(tool: tool, arguments: {})
    headers = { api_access_token: agent.access_token.token }

    get path, params: { conversation_id: conversation.display_id }, headers: headers
    expect(response.parsed_body.fetch('payload')).to be_empty

    post "#{path}/#{approval.id}/reject", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(approval.reload.status).to eq('pending')
  end

  it 'allows a reviewer to reject an approval and returns the updated record' do
    approval = Captain::Hitl::GatekeeperService.new(assistant: assistant, conversation: conversation).propose!(tool: tool, arguments: {})
    headers = { api_access_token: administrator.access_token.token }
    post "#{path}/#{approval.id}/reject", params: { reason: 'Wrong recipient' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'rejected', 'rejection_reason' => 'Wrong recipient')
    expect(approval.reload.reviewer_id).to eq(administrator.id)
  end
end
