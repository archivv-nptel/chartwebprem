class Captain::ResolutionEvent < ApplicationRecord
  self.table_name = 'captain_resolution_events'

  VERIFICATION_WINDOW = 24.hours
  ESTIMATED_HUMAN_COST = BigDecimal('6.50')
  OUTCOME_FEE = BigDecimal('0.70')

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :assistant, class_name: 'Captain::Assistant', optional: true

  enum :resolution_actor, { captain_ai: 'captain_ai', human_agent: 'human_agent', hybrid: 'hybrid' }, validate: true
  enum :verification_status, {
    pending: 'pending', verified: 'verified', invalidated_reopened: 'invalidated_reopened', invalidated_human_takeover: 'invalidated_human_takeover'
  }, validate: true

  validates :resolved_at, :episode_started_at, presence: true
  validate :same_account

  def verification_due_at
    resolved_at + VERIFICATION_WINDOW
  end

  private

  def same_account
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
    errors.add(:assistant, :invalid) if assistant && assistant.account_id != account_id
  end
end
