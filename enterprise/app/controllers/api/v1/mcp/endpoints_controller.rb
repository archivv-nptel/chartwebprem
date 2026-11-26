class Api::V1::Mcp::EndpointsController < Api::BaseController
  include MfaEnforcementGuard

  FEATURE_FLAG = 'captain_mcp_enterprise'.freeze
  MAX_REQUEST_BYTES = 64.kilobytes

  before_action :validate_request_origin
  before_action :set_account
  before_action :check_account_mfa_enforcement
  before_action :validate_protocol_version

  rescue_from JSON::ParserError, ActionDispatch::Http::Parameters::ParseError, with: :render_parse_error

  def handle
    return head :method_not_allowed, allow: 'POST' unless request.post?
    return head :unsupported_media_type unless request.media_type == 'application/json'

    body = request.body.read(MAX_REQUEST_BYTES + 1).to_s
    return head :content_too_large if body.bytesize > MAX_REQUEST_BYTES

    result = dispatcher.dispatch(JSON.parse(body))
    result ? render(json: result) : head(:accepted)
  end

  private

  # External MCP clients authenticate with the same API tokens as other API consumers. Dashboard sessions are not used.
  def authenticate_by_access_token?
    true
  end

  def validate_request_origin
    origin = request.origin
    return if origin.nil? || origin == ENV.fetch('FRONTEND_URL', nil)

    head :forbidden
  end

  def set_account
    account_id = request.headers['X-Chatwoot-Account-Id']
    return head :bad_request unless account_id&.match?(/\A[1-9]\d{0,18}\z/)

    membership = Current.user.account_users.find_by(account_id: account_id)
    account = membership&.account
    return head :forbidden unless account && mcp_account?(account)

    Current.account = account
    Current.account_user = membership
  end

  def mcp_account?(account)
    account.active? && account.api_and_webhooks_enabled? && account.feature_enabled?(FEATURE_FLAG)
  end

  def validate_protocol_version
    version = request.headers['MCP-Protocol-Version']
    head :bad_request if version && ::Captain::Mcp::ServerDispatcher::PROTOCOL_VERSIONS.exclude?(version)
  end

  def dispatcher
    ::Captain::Mcp::ServerDispatcher.new(account: Current.account, user: Current.user, account_user: Current.account_user)
  end

  def render_parse_error
    render json: ::Captain::Mcp::ServerDispatcher.parse_error, status: :bad_request
  end
end
