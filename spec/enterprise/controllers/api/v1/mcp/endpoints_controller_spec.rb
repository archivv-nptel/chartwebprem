require 'rails_helper'

RSpec.describe 'Enterprise MCP endpoint', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:headers) { { 'Authorization' => "Bearer #{user.access_token.token}", 'X-Chatwoot-Account-Id' => account.id.to_s } }
  let(:contact) { create(:contact, account: account, name: 'Ada Example', email: 'ada@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  before { account.enable_features!(Api::V1::Mcp::EndpointsController::FEATURE_FLAG) }

  def rpc(method, params = {}, id: 'request-1', request_headers: headers)
    message = { jsonrpc: '2.0', method: method, params: params }
    message[:id] = id unless id.nil?
    post '/api/v1/mcp', params: message, headers: request_headers, as: :json
  end

  def result_text
    JSON.parse(response.parsed_body.fetch('result').fetch('content').sole.fetch('text'))
  end

  it 'initializes a stateless server, accepts the client notification and lists the tools' do
    rpc('initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'Test', version: '1' } })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('jsonrpc' => '2.0', 'id' => 'request-1')
    expect(response.parsed_body.dig('result', 'protocolVersion')).to eq('2025-03-26')

    rpc('notifications/initialized', id: nil)
    expect(response).to have_http_status(:accepted)
    expect(response.body).to be_empty

    rpc('tools/list', request_headers: headers.merge('MCP-Protocol-Version' => '2025-03-26'))
    expect(response.parsed_body.dig('result', 'tools').pluck('name')).to contain_exactly(
      'chatwoot_search_conversations', 'chatwoot_add_private_note', 'chatwoot_get_contact_profile'
    )
  end

  it 'requires a valid API token and explicit account membership' do
    rpc('tools/list', request_headers: {})
    expect(response).to have_http_status(:unauthorized)

    rpc('tools/list', request_headers: headers.except('X-Chatwoot-Account-Id'))
    expect(response).to have_http_status(:bad_request)

    rpc('tools/list', request_headers: headers.merge('X-Chatwoot-Account-Id' => create(:account).id.to_s))
    expect(response).to have_http_status(:forbidden)
  end

  it 'offers discovery to current MCP clients' do
    url = 'https://chatwoot.example.com/api/v1/mcp'
    app = lambda do |env|
      # WebMock supplies a synthetic Rack session. Rails builds its own session from the request.
      env.delete('rack.session')
      Rails.application.call(env.merge('REMOTE_ADDR' => '127.0.0.1'))
    end
    stub_request(:post, url).to_rack(app)
    client = RubyLLM.context.mcp(url: url, name: 'chatwoot', headers: headers.merge('Accept-Encoding' => 'identity'))

    expect(client.tools.map(&:server_name)).to include('chatwoot_search_conversations')
    expect(a_request(:post, url).with(headers: { 'MCP-Protocol-Version' => '2026-07-28', 'Mcp-Method' => 'server/discover' })).to have_been_made.once
  end

  it 'refuses the endpoint when the account disables it' do
    account.disable_features!(Api::V1::Mcp::EndpointsController::FEATURE_FLAG)
    rpc('tools/list')
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects untrusted origins and unsupported protocol versions' do
    rpc('tools/list', request_headers: headers.merge('Origin' => 'https://other.example.com'))
    expect(response).to have_http_status(:forbidden)

    rpc('tools/list', request_headers: headers.merge('MCP-Protocol-Version' => 'unsupported'))
    expect(response).to have_http_status(:bad_request)
  end

  it 'rejects GET and DELETE because the server does not create sessions or SSE streams' do
    get '/api/v1/mcp', headers: headers
    expect(response).to have_http_status(:method_not_allowed)

    delete '/api/v1/mcp', headers: headers
    expect(response).to have_http_status(:method_not_allowed)
  end

  it 'returns a JSON-RPC error for an invalid envelope or malformed JSON' do
    post '/api/v1/mcp', params: { jsonrpc: '1.0', id: 1, method: 'tools/list' }, headers: headers, as: :json
    expect(response.parsed_body).to include('error' => { 'code' => -32_600, 'message' => 'Invalid request' }, 'id' => nil)

    post '/api/v1/mcp', params: '{', headers: headers.merge('CONTENT_TYPE' => 'application/json')
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to include('error' => { 'code' => -32_700, 'message' => 'Parse error' }, 'id' => nil)
  end

  it 'returns only matching conversations in accessible inboxes' do
    create(:inbox_member, user: user, inbox: conversation.inbox)
    create(:conversation, account: account, contact: contact)
    create(:conversation, account: account, inbox: conversation.inbox)

    rpc('tools/call', { name: 'chatwoot_search_conversations', arguments: { query: 'ADA', limit: 3 } })

    expect(result_text.pluck('display_id')).to eq([conversation.display_id])
  end

  it 'opens only permitted resources and contact histories' do
    uri = "chatwoot://conversations/#{conversation.display_id}"
    rpc('resources/read', { uri: uri })
    expect(response.parsed_body.dig('error', 'code')).to eq(-32_002)

    rpc('tools/call', { name: 'chatwoot_get_contact_profile', arguments: { email: contact.email } })
    expect(response.parsed_body.dig('error', 'code')).to eq(-32_002)

    create(:inbox_member, user: user, inbox: conversation.inbox)
    rpc('resources/read', { uri: uri })
    expect(response.parsed_body.dig('result', 'contents', 0, 'uri')).to eq(uri)

    rpc('tools/call', { name: 'chatwoot_get_contact_profile', arguments: { email: contact.email } })
    expect(result_text['conversations'].pluck('display_id')).to eq([conversation.display_id])
  end

  it 'writes only a private note and only when requested by an authorized user' do
    params = { name: 'chatwoot_add_private_note', arguments: { conversation_display_id: conversation.display_id, content: 'Internal note' } }
    expect { rpc('tools/call', params) }.not_to change(Message, :count)
    expect(response.parsed_body.dig('error', 'code')).to eq(-32_002)

    create(:inbox_member, user: user, inbox: conversation.inbox)
    expect { rpc('tools/call', params, id: nil) }.not_to change(Message, :count)
    expect(response).to have_http_status(:accepted)

    expect { rpc('tools/call', params) }.to change(Message, :count).by(1)
    expect(conversation.messages.find(result_text.fetch('message_id'))).to have_attributes(private: true, sender: user, content: 'Internal note')
  end
end
