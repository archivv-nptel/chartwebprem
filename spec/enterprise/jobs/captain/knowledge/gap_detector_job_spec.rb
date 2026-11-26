require 'rails_helper'

RSpec.describe Captain::Knowledge::GapDetectorJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:portal) { create(:portal, account: account) }
  let(:inbox) { create(:inbox, account: account, portal: portal) }
  let(:router) { instance_double(Captain::Llm::RouterService) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }
  let(:vector) { [1.0] + Array.new(1535, 0.0) }

  def resolved_ticket(message, selected_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: selected_inbox)
    create(:message, account: account, conversation: conversation, content: message)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'Follow these settings.')
    create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true, content: 'private note')
    conversation.update!(status: :resolved)
    conversation
  end

  def log_outcome(conversation, reopened: false)
    ConversationOutcome.create!(
      account: account, assistant: assistant, inbox: conversation.inbox, conversation: conversation,
      episode_trigger: reopened ? :reopen : :initial, started_at: 1.day.ago, handoff_at: reopened ? nil : 1.day.ago
    )
  end

  it 'drafts a recurring topic from recent handoffs and reopens within the same portal' do
    account.enable_features!(:captain_self_healing_kb)
    allow(Captain::Llm::RouterService).to receive(:new).with(account).and_return(router)
    allow(router).to receive(:chat).and_return(
      content: { title: 'Reset your password', markdown: 'Change it in Settings.', confidence: 0.8 }.to_json
    )
    allow(Captain::Llm::EmbeddingService).to receive(:new).with(account_id: account.id).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).with(/Password reset/).and_return(vector)
    allow(embedding_service).to receive(:get_embedding).with(/Subscription question/).and_return(vector.rotate)

    tickets = Array.new(3) { resolved_ticket('Password reset') }
    log_outcome(tickets.first, reopened: true)
    tickets.drop(1).each { |ticket| log_outcome(ticket) }
    log_outcome(resolved_ticket('Subscription question'))
    log_outcome(resolved_ticket('Password reset', selected_inbox: create(:inbox, account: account)))

    expect { described_class.perform_now(account.id) }.not_to change(Article, :count)

    expect(account.captain_kb_proposals.sole).to have_attributes(
      portal: portal, source_conversation_ids: tickets.map(&:id).sort, status: 'open', confidence_score: 0.8
    )
    expect(embedding_service).to have_received(:get_embedding).exactly(4).times
    expect(embedding_service).not_to have_received(:get_embedding).with(/private note/)
    expect(router).not_to have_received(:chat).with(hash_including(messages: array_including(hash_including(content: /private note/))))
  end
end
