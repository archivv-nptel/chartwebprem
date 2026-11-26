class Captain::SimulationRun < ApplicationRecord
  self.table_name = 'captain_simulation_runs'

  MAX_TICKETS = 1000
  MAX_PROMPT_LENGTH = 12_000

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :playbook, class_name: 'Captain::Playbook', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :results, class_name: 'Captain::SimulationResult', dependent: :delete_all, inverse_of: :simulation_run

  enum :status, %w[queued running completed failed].index_by(&:itself), validate: true

  validate :validate_associations
  validate :validate_candidate_config, if: :will_save_change_to_candidate_config?
  validate :validate_ticket_filter, if: :will_save_change_to_ticket_filter?

  def ticket_scope
    scope = account.conversations.resolved
    scope = scope.where(inbox_id: ticket_filter['inbox_id']) if ticket_filter.key?('inbox_id')
    scope.reorder(last_activity_at: :desc, id: :desc).limit(ticket_filter.fetch('limit', MAX_TICKETS))
  end

  private

  def validate_associations
    errors.add(:assistant, :invalid) if assistant && assistant.account_id != account_id
    return unless playbook

    errors.add(:playbook, :invalid) unless playbook.account_id == account_id && playbook.assistant_id == assistant_id
  end

  def validate_candidate_config
    return errors.add(:candidate_config, :invalid) unless candidate_config.is_a?(Hash)

    errors.add(:candidate_config, :invalid) unless candidate_config.all? { |key, value| valid_candidate_option?(key, value) }
  end

  def valid_candidate_option?(key, value)
    case key
    when 'system_prompt' then bounded_text?(value, MAX_PROMPT_LENGTH)
    when 'model_id' then bounded_text?(value, 255) && value.present?
    when 'temperature' then value.is_a?(Numeric) && value.between?(0, 2)
    else false
    end
  end

  def bounded_text?(value, maximum_length)
    value.is_a?(String) && value.length <= maximum_length
  end

  def validate_ticket_filter
    return errors.add(:ticket_filter, :invalid) unless ticket_filter.is_a?(Hash)

    errors.add(:ticket_filter, :invalid) unless ticket_filter.all? { |key, value| valid_ticket_option?(key, value) }
  end

  def valid_ticket_option?(key, value)
    return false unless value.is_a?(Integer)

    case key
    when 'limit' then value.between?(1, MAX_TICKETS)
    when 'inbox_id' then account&.inboxes&.exists?(id: value)
    else false
    end
  end
end
