class Captain::Playbooks::AutomaticRunService
  def initialize(assistant:, conversation:, responding_to_message_id:)
    @assistant = assistant
    @conversation = conversation
    @responding_to_message_id = responding_to_message_id
  end

  def handled?
    return false unless @responding_to_message_id && @assistant.account.feature_enabled?(Captain::Playbook::FEATURE)

    message = @conversation.messages.captain_response_triggering.find_by(id: @responding_to_message_id)
    return false unless message

    run = waiting_run
    if run
      engine(run.playbook).resume_user!(run, message)
      return true
    end

    playbook = matching_playbook(message)
    return false unless playbook

    engine(playbook).execute!(initial_context: { 'customer_message' => message.content }, trigger_message: message)
    true
  end

  private

  def assistant_playbooks
    @assistant.account.captain_playbooks.where(assistant: @assistant)
  end

  def waiting_run
    Captain::PlaybookRun.where(playbook: assistant_playbooks, conversation: @conversation, dry_run: false)
                        .waiting_user.order(id: :desc).first
  end

  def matching_playbook(message)
    assistant_playbooks.published.find_each.find { |playbook| playbook.matches_message?(message) }
  end

  def engine(playbook)
    Captain::Playbooks::EngineService.new(playbook: playbook, conversation: @conversation)
  end
end
