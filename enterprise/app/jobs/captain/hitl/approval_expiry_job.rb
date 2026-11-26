class Captain::Hitl::ApprovalExpiryJob < ApplicationJob
  def perform(approval_id)
    approval = Captain::ActionApproval.find_by(id: approval_id)
    return unless approval

    expired = approval.with_lock do
      next false unless approval.status == 'pending' && approval.expires_at <= Time.current

      approval.update!(status: 'expired')
    end
    return unless expired

    Captain::Hitl::ApprovalEvents.broadcast(approval, Captain::Hitl::GatekeeperService::UPDATED_EVENT)
    return unless approval.playbook_run

    Captain::Playbooks::EngineService.new(playbook: approval.playbook_run.playbook, conversation: approval.conversation).resume_approval!(approval)
  end
end
