class Captain::SwarmHandoff < ApplicationRecord
  self.table_name = 'captain_swarm_handoffs'

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :from_assistant, class_name: 'Captain::Assistant', optional: true
  belongs_to :to_assistant, class_name: 'Captain::Assistant', optional: true

  validates :handoff_type, inclusion: { in: %w[agent_to_agent agent_to_human] }
  validates :hop_count, numericality: { only_integer: true, in: 1..4 }
  validates :to_assistant, presence: true, if: -> { handoff_type == 'agent_to_agent' }
  validate :records_belong_to_account

  private

  def records_belong_to_account
    %i[conversation from_assistant to_assistant].each do |name|
      record = public_send(name)
      errors.add(name, :invalid) if record && record.account_id != account_id
    end
  end
end
