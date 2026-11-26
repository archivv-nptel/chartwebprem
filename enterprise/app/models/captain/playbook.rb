class Captain::Playbook < ApplicationRecord
  self.table_name = 'captain_playbooks'

  FEATURE = 'captain_agentic_playbooks'.freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'Captain::Assistant'
  has_many :runs, class_name: 'Captain::PlaybookRun', dependent: :destroy, inverse_of: :playbook

  enum :status, %w[draft published archived].index_by(&:itself), default: :draft, validate: true

  validates :name, presence: true, length: { maximum: 150 }
  validate :validate_configuration

  def publish!
    with_lock { update!(status: :published, version: version + 1) }
  end

  def matches_message?(message)
    return false unless published? && trigger_conditions['automatic'] == true

    match = trigger_conditions['message_contains']
    match.blank? || message.content.to_s.downcase.include?(match.downcase)
  end

  private

  def validate_configuration
    errors.add(:assistant, :invalid) unless assistant&.account_id == account_id
    errors.add(:trigger_conditions, :invalid) unless valid_trigger_conditions?
    problem = Captain::Playbooks::Graph.new(graph_definition).problem(require_nodes: published?)
    errors.add(:graph_definition, problem) if problem
  end

  def valid_trigger_conditions?
    return false unless trigger_conditions.is_a?(Hash) && (trigger_conditions.keys - %w[automatic message_contains]).empty?

    automatic = trigger_conditions.fetch('automatic', false)
    match = trigger_conditions.fetch('message_contains', '')
    [true, false].include?(automatic) && match.is_a?(String) && match.length <= 300
  end
end
