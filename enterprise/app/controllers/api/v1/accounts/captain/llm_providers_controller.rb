class Api::V1::Accounts::Captain::LlmProvidersController < Api::V1::Accounts::Captain::AgenticBaseController
  PROVIDER_ATTRIBUTES = %i[id name provider_type model_id endpoint_url region zero_data_retention priority enabled routing_rules].freeze
  CREDENTIAL_ATTRIBUTES = [:api_key, :aws_access_key_id, :aws_secret_access_key, :aws_session_token, :project_id,
                           { service_account_key: [:client_email, :private_key] }].freeze

  before_action { authorize_captain_feature!(:captain_byom_routing, require_admin: true) }
  before_action :set_provider, only: [:show, :update, :destroy, :test_connection]

  def index
    render json: { payload: providers.order(:priority, :id).page(params[:page]).per(50).map { |provider| serialize(provider) } }
  end

  def show
    render json: serialize(@provider)
  end

  def create
    @provider = providers.new
    save_provider!
    render json: serialize(@provider), status: :created
  end

  def update
    @provider.with_lock { save_provider! }
    render json: serialize(@provider)
  end

  def destroy
    @provider.destroy!
    head :no_content
  end

  def test_connection
    result = ::Captain::Llm::RouterService.new(Current.account).test_connection(@provider)
    render json: { ok: true, model: result[:model] }
  rescue *::Captain::Llm::ProviderChain::ERRORS
    render json: { ok: false, error: I18n.t('errors.captain.llm_connection_failed') }, status: :unprocessable_entity
  end

  private

  def providers
    Current.account.captain_llm_provider_configs
  end

  def set_provider
    @provider = providers.find(params[:id])
  end

  def save_provider!
    permitted = provider_params
    credentials = permitted.delete(:credentials)
    @provider.assign_attributes(permitted)
    @provider.credentials = credentials.to_h if credentials
    @provider.save!
  end

  def provider_params
    fields = PROVIDER_ATTRIBUTES - [:id, :routing_rules]
    raw = params.require(:llm_provider)
    permitted = raw.permit(*fields, routing_rules: [:task, :max_tokens], credentials: CREDENTIAL_ATTRIBUTES)
    permitted[:credentials] = params.permit(credentials: CREDENTIAL_ATTRIBUTES)[:credentials] if params.key?(:credentials) && !raw.key?(:credentials)
    permitted
  end

  def serialize(provider)
    provider.slice(*PROVIDER_ATTRIBUTES).merge('credentials_configured' => provider.credentials_configured?)
  end
end
