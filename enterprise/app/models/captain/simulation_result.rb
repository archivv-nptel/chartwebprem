class Captain::SimulationResult < ApplicationRecord
  self.table_name = 'captain_simulation_results'

  belongs_to :simulation_run, class_name: 'Captain::SimulationRun', inverse_of: :results
  belongs_to :conversation, class_name: '::Conversation'

  delegate :display_id, to: :conversation, prefix: true, allow_nil: true

  validates :hallucination_score, :policy_adherence_score, inclusion: { in: 0.0..1.0 }
  validate :conversation_belongs_to_account

  private

  def conversation_belongs_to_account
    return if conversation && simulation_run && conversation.account_id == simulation_run.account_id

    errors.add(:conversation, :invalid)
  end
end
