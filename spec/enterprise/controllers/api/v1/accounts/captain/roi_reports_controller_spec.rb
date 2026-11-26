require 'rails_helper'

RSpec.describe 'Captain resolution outcomes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/roi_report" }

  def add_event(owner, actor, **attributes)
    owner.captain_resolution_events.create!(
      conversation: create(:conversation, account: owner), episode_started_at: 3.days.ago, resolved_at: 2.days.ago,
      resolution_actor: actor, verification_status: :verified, **attributes
    )
  end

  it 'requires the flag and account administrator role' do
    agent_headers = agent.create_new_auth_token
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)

    Account.find(account.id).enable_features!(:captain_outcome_metering)
    get path, headers: agent_headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'reports verified totals, estimated fees and CSAT within the selected account' do
    account.enable_features!(:captain_outcome_metering)
    add_event(account, :captain_ai, csat_rating: 4, billable_fee_usd: 0.70)
    add_event(account, :human_agent, csat_rating: 5)
    add_event(account, :captain_ai, verification_status: :pending)
    add_event(create(:account), :captain_ai, csat_rating: 1)

    get path, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'total_verified_resolutions' => 2, 'ai_verified_resolutions' => 1, 'deflection_rate_pct' => 50.0,
      'net_roi_savings_usd' => 5.8, 'csat_parity' => { 'captain_ai_csat' => 4.0, 'human_agent_csat' => 5.0, 'delta' => -1.0 }
    )
  end

  it 'rejects invalid report dates' do
    account.enable_features!(:captain_outcome_metering)
    get path, headers: admin.create_new_auth_token, params: { from: 'bad-date' }

    expect(response).to have_http_status(:unprocessable_content)
  end
end
