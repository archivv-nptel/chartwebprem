class Api::V1::Accounts::Captain::KbProposalsController < Api::V1::Accounts::Captain::AgenticBaseController
  before_action { authorize_captain_feature!(:captain_self_healing_kb, require_admin: true) }
  before_action :set_proposal, except: [:index]

  rescue_from ::Captain::Knowledge::ProposalService::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end

  def index
    proposals = Current.account.captain_kb_proposals.order(created_at: :desc, id: :desc).page(params[:page]).per(25)
    render json: { payload: proposals.as_json(except: internal_fields), total_count: proposals.total_count }
  end

  def show
    render_proposal
  end

  def update
    proposal_service.edit!(proposal: @proposal, attributes: params.require(:kb_proposal).permit(:proposed_title, :proposed_markdown))
    render_proposal
  end

  def merge
    proposal_service.merge!(proposal: @proposal, reviewer: Current.user)
    render_proposal
  end

  def reject
    proposal_service.reject!(proposal: @proposal, reviewer: Current.user)
    render_proposal
  end

  private

  def set_proposal
    @proposal = Current.account.captain_kb_proposals.find(params[:id])
  end

  def proposal_service
    ::Captain::Knowledge::ProposalService.new(Current.account)
  end

  def render_proposal
    render json: @proposal.as_json(except: internal_fields)
  end

  def internal_fields
    %i[cluster_centroid source_digest target_article_digest]
  end
end
