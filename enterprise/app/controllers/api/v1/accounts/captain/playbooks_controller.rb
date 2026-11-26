class Api::V1::Accounts::Captain::PlaybooksController < Api::V1::Accounts::Captain::AgenticBaseController
  before_action { authorize_captain_feature!(:captain_agentic_playbooks, require_admin: true) }
  before_action :set_playbook, only: %i[show update destroy publish execute runs]

  def index
    render json: { payload: playbooks.order(id: :desc).page(params[:page]).per(25) }
  end

  def show
    render json: @playbook
  end

  def create
    render json: playbooks.create!(playbook_params), status: :created
  end

  def update
    @playbook.with_lock do
      @playbook.assign_attributes(playbook_params)
      @playbook.status = :draft if @playbook.published? && @playbook.changed?
      @playbook.save!
    end
    render json: @playbook
  end

  def destroy
    # Keep existing runs and approvals for audit. Archived playbooks cannot start new runs.
    @playbook.update!(status: :archived)
    head :no_content
  end

  def publish
    @playbook.publish!
    render json: @playbook
  end

  def runs
    runs = @playbook.runs.includes(:conversation).order(id: :desc).page(params[:page]).per(25)
    render json: { payload: runs.map(&:api_payload) }
  end

  def execute
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    run = Captain::Playbooks::EngineService.new(playbook: @playbook, conversation: conversation, dry_run: dry_run?)
                                           .execute!(initial_context: execution_context)
    render json: run.api_payload, status: :created
  rescue Captain::Playbooks::EngineService::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def playbooks
    Current.account.captain_playbooks.where.not(status: :archived)
  end

  def set_playbook
    @playbook = playbooks.find(params[:id])
  end

  def playbook_params
    record = params.require(:playbook)
    %i[graph_definition trigger_conditions].each do |field|
      if record.key?(field) && !record[field].is_a?(ActionController::Parameters)
        raise Captain::Playbooks::EngineService::Unavailable, "#{field} must be an object"
      end
    end
    record.permit(:assistant_id, :name, :description, trigger_conditions: {}, graph_definition: {})
  end

  def dry_run?
    value = params.fetch(:dry_run, false)
    raise Captain::Playbooks::EngineService::Unavailable, 'dry_run must be a boolean' unless [true, false].include?(value)

    value
  end

  def execution_context
    value = params.fetch(:context, ActionController::Parameters.new)
    raise Captain::Playbooks::EngineService::Unavailable, 'Context must be an object' unless value.is_a?(ActionController::Parameters)

    value.to_unsafe_h.to_h
  end

  rescue_from Captain::Playbooks::EngineService::Unavailable do |error|
    render json: { error: error.message }, status: :unprocessable_content
  end
end
