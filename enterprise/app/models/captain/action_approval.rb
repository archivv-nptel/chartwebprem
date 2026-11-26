# == Schema Information
#
# Table name: captain_action_approvals
#
#  id                       :bigint           not null, primary key
#  executed_at              :datetime
#  execution_result         :jsonb
#  expires_at               :datetime         not null
#  modified_arguments       :jsonb
#  proposed_arguments       :jsonb            not null
#  rationale                :text
#  rejection_reason         :text
#  reviewed_at              :datetime
#  risk_level               :string           default("high"), not null
#  status                   :string           default("pending"), not null
#  tool_definition_digest   :string
#  tool_name                :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  assistant_id             :bigint           not null
#  conversation_id          :bigint           not null
#  custom_tool_id           :bigint
#  mcp_tool_id              :bigint
#  playbook_run_id          :bigint
#  responding_to_message_id :bigint
#  reviewer_id              :bigint
#
# Indexes
#
#  index_captain_action_approvals_on_account_id             (account_id)
#  index_captain_action_approvals_on_account_id_and_status  (account_id,status)
#  index_captain_action_approvals_on_assistant_id           (assistant_id)
#  index_captain_action_approvals_on_conversation_id        (conversation_id)
#  index_captain_action_approvals_on_custom_tool_id         (custom_tool_id)
#  index_captain_action_approvals_on_mcp_tool_id            (mcp_tool_id)
#  index_captain_action_approvals_on_playbook_run_id        (playbook_run_id)
#  index_captain_action_approvals_on_reviewer_id            (reviewer_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (assistant_id => captain_assistants.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (custom_tool_id => captain_custom_tools.id) ON DELETE => nullify
#  fk_rails_...  (mcp_tool_id => captain_mcp_tools.id) ON DELETE => nullify
#  fk_rails_...  (playbook_run_id => captain_playbook_runs.id) ON DELETE => nullify
#  fk_rails_...  (reviewer_id => users.id) ON DELETE => nullify
#
class Captain::ActionApproval < ApplicationRecord
  self.table_name = 'captain_action_approvals'

  STATUSES = %w[pending approved rejected executed failed expired].freeze
  RISK_LEVELS = %w[high critical].freeze

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :reviewer, class_name: 'User', optional: true
  belongs_to :mcp_tool, class_name: 'Captain::McpTool', optional: true
  belongs_to :custom_tool, class_name: 'Captain::CustomTool', optional: true
  belongs_to :playbook_run, class_name: 'Captain::PlaybookRun', optional: true

  validates :tool_name, :tool_definition_digest, :expires_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validate :validate_ownership, :validate_run_ownership, on: :create

  def effective_arguments
    modified_arguments || proposed_arguments
  end

  def reviewable?
    status == 'pending' && expires_at.future?
  end

  def newer_message_arrived?
    return false unless responding_to_message_id

    ::Message.uncached { conversation.messages.captain_response_triggering.exists?(id: (responding_to_message_id + 1)..) }
  end

  def api_payload
    slice(:id, :conversation_id, :assistant_id, :tool_name, :risk_level, :status, :proposed_arguments, :modified_arguments,
          :rationale, :expires_at, :reviewed_at, :executed_at, :rejection_reason)
      .merge(conversation_display_id: conversation.display_id, status: review_status)
  end

  private

  def review_status
    status == 'pending' && expires_at.past? ? 'expired' : status
  end

  def validate_ownership
    errors.add(:conversation, :invalid) unless conversation&.account_id == account_id
    errors.add(:assistant, :invalid) unless assistant&.account_id == account_id
    errors.add(:base, :invalid) unless valid_tool_owner?
  end

  def validate_run_ownership
    return unless playbook_run

    errors.add(:playbook_run, :invalid) unless playbook_run.account_id == account_id && playbook_run.conversation_id == conversation_id
  end

  def valid_tool_owner?
    return mcp_tool.account_id == account_id && mcp_tool.mcp_server.assistant_id == assistant_id if mcp_tool && !custom_tool
    return custom_tool.account_id == account_id && custom_tool.assistant_id == assistant_id if custom_tool && !mcp_tool

    false
  end
end
