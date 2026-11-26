class Captain::Knowledge::GapDetectorJob < ApplicationJob
  queue_as :low

  MAX_CONVERSATIONS = 30
  MAX_PROPOSALS_PER_PORTAL = 3
  LOOKBACK = 7.days

  def perform(account_id)
    account = Account.feature_captain_self_healing_kb.find_by(id: account_id)
    return unless account

    candidates = recent_candidates(account)
    candidates.group_by { |conversation| conversation.inbox.portal_id }.each do |portal_id, conversations|
      next if conversations.length < Captain::Knowledge::GapClusterer::MIN_CLUSTER_SIZE

      portal = account.portals.active.find_by(id: portal_id)
      next unless portal

      create_proposals(account, portal, conversations)
    end
  end

  private

  def recent_candidates(account)
    cutoff = LOOKBACK.ago
    observations = Captain::FaqObservation.attached.where(account_id: account.id, created_at: cutoff..)
    conversations = account.conversations.resolved
    conversations.where(id: affected_conversation_ids(account, cutoff)).or(conversations.where(id: observations.select(:conversation_id)))
                 .joins(:inbox).merge(account.inboxes.where.not(portal_id: nil)).includes(:inbox)
                 .reorder(last_activity_at: :desc, id: :desc).limit(MAX_CONVERSATIONS).to_a
  end

  def affected_conversation_ids(account, cutoff)
    outcomes = ConversationOutcome.where(account_id: account.id)
    outcomes.where(handoff_at: cutoff..).or(outcomes.trigger_reopen.where(started_at: cutoff..)).select(:conversation_id)
  end

  def create_proposals(account, portal, conversations)
    clusterer = Captain::Knowledge::GapClusterer.new(account)
    service = Captain::Knowledge::ProposalService.new(account)
    clusterer.clusters(conversations).sort_by { |cluster| -cluster.fetch(:samples).length }.first(MAX_PROPOSALS_PER_PORTAL).each do |cluster|
      service.generate_from_cluster!(portal: portal, **cluster)
    end
  end
end
