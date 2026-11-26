class Captain::PlaybookRun < ApplicationRecord
  self.table_name = 'captain_playbook_runs'

  belongs_to :account
  belongs_to :playbook, class_name: 'Captain::Playbook', inverse_of: :runs
  belongs_to :conversation, class_name: '::Conversation', optional: true
  has_many :action_approvals, class_name: 'Captain::ActionApproval', dependent: :nullify, inverse_of: :playbook_run

  enum :status, %w[running waiting_hitl waiting_user completed escalated failed].index_by(&:itself), default: :running, validate: true

  validate :validate_ownership

  def record_step!(node, branch:, next_state:, metadata: {})
    event = { node_id: node.fetch('id'), node_type: node.fetch('type'), outcome: branch, metadata: metadata, timestamp: Time.current.iso8601 }
    update!(execution_trace: execution_trace + [event], **next_state)
  end

  def api_payload
    slice(:id, :playbook_id, :status, :current_node_id, :execution_trace, :dry_run, :created_at, :updated_at)
      .merge(conversation_display_id: conversation&.display_id)
  end

  private

  def validate_ownership
    errors.add(:playbook, :invalid) unless playbook&.account_id == account_id
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
  end
end
