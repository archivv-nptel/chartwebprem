require 'rails_helper'

RSpec.describe Captain::Knowledge::ProposalService do
  let(:account) { create(:account) }
  let(:portal) { create(:portal, account: account) }
  let(:reviewer) { create(:user, account: account, role: :administrator) }
  let(:router) { instance_double(Captain::Llm::RouterService) }
  let(:vector) { [1.0] + Array.new(1535, 0.0) }
  let(:draft) { { title: 'Reset your password', markdown: "Open Settings\nUse password reset\n", confidence: 0.9 } }
  let(:samples) do
    create_list(:conversation, 3, account: account, status: :resolved).map do |conversation|
      { conversation_id: conversation.id, transcript: 'Question and human resolution' }
    end
  end

  before do
    allow(Captain::Llm::RouterService).to receive(:new).with(account).and_return(router)
    allow(router).to receive(:chat).and_return(content: draft.to_json)
  end

  it 'deduplicates drafts and publishes only after review' do
    service = described_class.new(account)
    expect do
      2.times { service.generate_from_cluster!(portal: portal, samples: samples, centroid: vector) }
    end.not_to change(Article, :count)

    proposal = account.captain_kb_proposals.sole
    expect(proposal.unified_diff).to include('@@ -0,0 +1,2 @@', '+Use password reset')

    expect { service.merge!(proposal: proposal, reviewer: reviewer) }.to change(Article, :count).by(1)
    expect(proposal.reload).to have_attributes(
      status: 'merged', target_article: have_attributes(title: draft[:title], content: draft[:markdown], status: 'published', author: reviewer)
    )
    expect(router).to have_received(:chat).once
    expect { service.merge!(proposal: proposal, reviewer: reviewer) }.to raise_error(StandardError, 'proposal_closed') do |error|
      expect(error.class.name).to eq('Captain::Knowledge::ProposalService::Conflict')
    end
  end

  it 'rejects a stale update if someone edited the source article after the proposal was drafted' do
    article = create(:article, account: account, portal: portal, author: reviewer, content: 'Original instructions')
    article.article_embeddings.create!(term: 'password reset', embedding: vector)
    service = described_class.new(account)
    proposal = service.generate_from_cluster!(portal: portal, samples: samples, centroid: vector)

    expect(proposal.target_article).to eq(article)
    article.update!(draft_content: 'Manual draft in progress')

    expect { service.merge!(proposal: proposal, reviewer: reviewer) }.to raise_error(StandardError, 'source_article_changed') do |error|
      expect(error.class.name).to eq('Captain::Knowledge::ProposalService::Conflict')
    end
    expect(proposal.reload).to be_open
    expect(article.reload).to have_attributes(content: 'Original instructions', draft_content: 'Manual draft in progress')
  end

  it 'rejects drafts for a portal in another account before calling the model' do
    other_portal = create(:portal)

    expect { described_class.new(account).generate_from_cluster!(portal: other_portal, samples: samples, centroid: vector) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(router).not_to have_received(:chat)
  end
end
