class Api::V1::Accounts::Captain::SimulationsController < Api::V1::Accounts::Captain::AgenticBaseController
  before_action { authorize_captain_feature!(:captain_simulations, require_admin: true) }

  def index
    runs = Current.account.captain_simulation_runs.order(created_at: :desc, id: :desc)
    runs = runs.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    render json: { payload: runs.limit(20).as_json(except: :ticket_ids) }
  end

  def show
    run = Current.account.captain_simulation_runs.find(params[:id])
    results = run.results.includes(:conversation).order(:id).page(params[:page]).per(100)
    render json: run.as_json(except: :ticket_ids).merge(
      results: results.as_json(methods: :conversation_display_id), result_count: results.total_count
    )
  end

  def create
    assistant = Current.account.captain_assistants.find(params.require(:assistant_id))
    playbook = Current.account.captain_playbooks.find(params[:playbook_id]) if params[:playbook_id].present?
    run = Current.account.captain_simulation_runs.create!(
      assistant: assistant,
      playbook: playbook,
      created_by: Current.user,
      candidate_config: settings(:candidate_config, %i[system_prompt temperature model_id]),
      ticket_filter: settings(:ticket_filter, %i[limit inbox_id])
    )
    ::Captain::Simulations::RunnerJob.perform_later(run.id)
    render json: run.as_json(except: :ticket_ids), status: :accepted
  end

  private

  def settings(key, allowed)
    return {} unless params.key?(key)

    value = params[key]
    raise ActionController::ParameterMissing, key unless value.is_a?(ActionController::Parameters)

    permitted = value.permit(*allowed)
    raise ActionController::ParameterMissing, key unless value.keys.sort == permitted.keys.sort

    permitted.to_h
  end
end
