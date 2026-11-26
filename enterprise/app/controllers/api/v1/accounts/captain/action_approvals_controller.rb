class Api::V1::Accounts::Captain::ActionApprovalsController < Api::V1::Accounts::Captain::AgenticBaseController
  include Captain::Copilot::ConversationAccess

  before_action { authorize_captain_feature!(:captain_hitl_approvals) }
  before_action :set_approval, only: %i[show approve reject]

  def index
    approvals = accessible_approvals.includes(:conversation).order(id: :desc)
    approvals = approvals.joins(:conversation).where(conversations: { display_id: params[:conversation_id] }) if params[:conversation_id].present?
    render json: { payload: approvals.limit(50).map(&:api_payload) }
  end

  def show
    render json: @approval.api_payload
  end

  def approve
    modified_arguments = params[:modified_arguments]
    if params.key?(:modified_arguments) && !modified_arguments.is_a?(ActionController::Parameters)
      return render json: { error: 'Modified arguments must be an object' }, status: :unprocessable_content
    end

    approval = Captain::Hitl::ActionExecutorService.new.approve_and_execute!(
      approval: @approval, reviewer: Current.user, modified_arguments: modified_arguments&.to_unsafe_h&.to_h
    )
    render json: approval.api_payload
  rescue Captain::Hitl::ActionExecutorService::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def reject
    reason = params[:reason]
    if params.key?(:reason) && (!reason.is_a?(String) || reason.length > 1000)
      return render json: { error: 'Reason must be text of up to 1,000 characters' }, status: :unprocessable_content
    end

    approval = Captain::Hitl::ActionExecutorService.new.reject!(approval: @approval, reviewer: Current.user, reason: reason)
    render json: approval.api_payload
  rescue Captain::Hitl::ActionExecutorService::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def set_approval
    @approval = accessible_approvals.find(params[:id])
    authorize @approval.conversation, :show?
  end

  def accessible_approvals
    conversations = accessible_conversations(account: Current.account, user: Current.user)
    Current.account.captain_action_approvals.where(conversation_id: conversations.select(:id))
  end
end
