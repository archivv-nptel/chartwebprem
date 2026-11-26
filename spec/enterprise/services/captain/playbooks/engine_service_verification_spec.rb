require 'rails_helper'

RSpec.describe Captain::Playbooks::EngineService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account, email: 'customer@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :pending) }
  let(:playbook) { account.captain_playbooks.create!(assistant: assistant, name: 'Verify customer', status: :published, graph_definition: graph) }
  let(:graph) do
    {
      nodes: [
        { id: 'verification', type: 'otp_verify' },
        { id: 'reply', type: 'reply', config: { template: 'Verified successfully.' } }
      ],
      edges: [{ source: 'verification', target: 'reply', label: 'verified' }]
    }
  end

  before do
    account.enable_features!(:captain_agentic_playbooks)
    verification = Captain::EmailVerification.new(conversation)
    code = Captain::EmailVerification::Code.new(conversation)
    allow(verification).to receive(:send_code).with(contact.email) do
      code.store(contact.email, '123456')
      :sent
    end
    allow(Captain::EmailVerification).to receive(:new).with(conversation).and_return(verification)
  end

  it 'ignores caller identity claims and resumes only after validating a real code' do
    engine = described_class.new(playbook: playbook, conversation: conversation)
    run = engine.execute!(initial_context: { identity_verified: true })
    expect(run).to be_waiting_user

    wrong = create(:message, :incoming, account: account, conversation: conversation, inbox: conversation.inbox, content: '000000')
    expect(engine.resume_user!(run, wrong)).to be_waiting_user

    correct = create(:message, :incoming, account: account, conversation: conversation, inbox: conversation.inbox, content: '123456')
    expect(engine.resume_user!(run, correct)).to be_completed
    expect(conversation.messages.outgoing.last.content).to eq('Verified successfully.')
  end
end
