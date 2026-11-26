require 'rails_helper'

RSpec.describe 'Captain simulation API', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/captain/simulations" }

  before { account.enable_features!(:captain_simulations) }

  it 'queues an account-scoped simulation with a validated JSON candidate' do
    post path, params: { assistant_id: assistant.id, candidate_config: { system_prompt: 'Be concise.', temperature: 0.5 },
                         ticket_filter: { limit: 4 } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include('status' => 'queued', 'ticket_filter' => { 'limit' => 4 })
    expect(enqueued_jobs).to include(
      a_hash_including(job: an_object_having_attributes(name: 'Captain::Simulations::RunnerJob'), args: [response.parsed_body.fetch('id')])
    )
  end

  it 'rejects a foreign assistant even for administrators' do
    outsider = create(:captain_assistant)
    post path, params: { assistant_id: outsider.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(account.captain_simulation_runs).to be_empty
  end

  it 'forbids regular agents from viewing simulation data' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
