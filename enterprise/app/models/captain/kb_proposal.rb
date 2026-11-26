class Captain::KbProposal < ApplicationRecord
  self.table_name = 'captain_kb_proposals'

  belongs_to :account
  belongs_to :portal
  belongs_to :target_article, class_name: 'Article', optional: true
  belongs_to :reviewer, class_name: 'User', optional: true
  has_neighbors :cluster_centroid, normalize: true

  enum :proposal_type, %w[create_article update_article].index_by(&:itself), validate: true
  enum :status, %w[open merged rejected].index_by(&:itself), validate: true

  validates :proposed_title, presence: true, length: { maximum: 255 }
  validates :proposed_markdown, presence: true, length: { maximum: 30_000 }
  validates :confidence_score, inclusion: { in: 0.0..1.0 }
  validate :validate_associations

  private

  def validate_associations
    errors.add(:portal, :invalid) if portal && portal.account_id != account_id
    return unless target_article

    errors.add(:target_article, :invalid) unless target_article.account_id == account_id && target_article.portal_id == portal_id
  end
end
