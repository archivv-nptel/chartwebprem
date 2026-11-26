require 'rails_helper'

RSpec.describe 'Captain knowledge proposals API', type: :request do
  let(:account) { create(:account) }
  let(:portal) { create(:portal, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:proposal) do
    account.captain_kb_proposals.create!(
      portal: portal, proposal_type: :create_article, proposed_title: 'Reset password', proposed_markdown: 'Go to Settings.'
    )
  end
  let(:path) { "/api/v1/accounts/#{account.id}/captain/kb_proposals" }

  before { account.enable_features!(:captain_self_healing_kb) }

  it 'lets an administrator edit the proposed text and explicitly publish it' do
    headers = admin.create_new_auth_token
    patch "#{path}/#{proposal.id}", params: { kb_proposal: { proposed_markdown: 'Open your account settings.' } },
                                    headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['unified_diff']).to include('+Open your account settings.')

    expect do
      post "#{path}/#{proposal.id}/merge", headers: headers, as: :json
    end.to change(Article, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(proposal.reload.target_article).to have_attributes(status: 'published', content: 'Open your account settings.')
  end

  it 'prevents agents from publishing a proposal' do
    expect do
      post "#{path}/#{proposal.id}/merge", headers: agent.create_new_auth_token, as: :json
    end.not_to change(Article, :count)

    expect(response).to have_http_status(:forbidden)
    expect(proposal.reload).to be_open
  end
end
