class Captain::Playbooks::EngineService
  class Unavailable < StandardError; end

  def initialize(playbook:, conversation:, dry_run: false)
    @playbook = playbook
    @conversation = conversation
    @dry_run = dry_run
  end

  def execute!(initial_context: {}, trigger_message: nil)
    validate_execution!(trigger_message)
    graph = Captain::Playbooks::Graph.new(@playbook.graph_definition)
    problem = graph.problem(require_nodes: true)
    raise Unavailable, problem if problem

    context = initial_context.deep_stringify_keys.except('captain_message_id')
    trigger_message_id = trigger_message&.id
    context['captain_message_id'] = trigger_message_id || latest_customer_message_id
    attributes = {
      account: @playbook.account, conversation: @conversation, current_node_id: graph.entry.fetch('id'),
      graph_snapshot: @playbook.graph_definition, context_state: context, dry_run: @dry_run
    }
    return execute_once(attributes, trigger_message_id) if trigger_message_id && !@dry_run

    advance(@playbook.runs.create!(attributes))
  end

  def resume_approval!(approval)
    run = approval.playbook_run
    claimed = run.with_lock do
      next false unless valid_resume?(run, :waiting_hitl)
      next false unless run.execution_trace.last&.dig('metadata', 'approval_id') == approval.id

      resume_approval_step!(run, approval)
      true
    end
    advance(run) if claimed && run.running?
    run
  end

  def resume_user!(run, message)
    return run unless valid_resume?(run, :waiting_user) && message.conversation_id == @conversation.id

    claimed = run.with_lock { claim_user_response(run, message) }
    advance(run) if claimed && run.running?
    run
  end

  private

  def validate_execution!(message)
    raise Unavailable, 'Agentic playbooks are disabled' unless @playbook.account.feature_enabled?(Captain::Playbook::FEATURE)

    validate_conversation!(message)
    return if @dry_run

    raise Unavailable, 'Publish the playbook before starting a live run' unless @playbook.published?
    raise Unavailable, 'Live runs require a pending conversation' unless @conversation&.pending?
  end

  def latest_customer_message_id
    return if @dry_run

    @conversation.messages.captain_response_triggering.maximum(:id)
  end

  def validate_conversation!(message)
    raise Unavailable, 'The conversation is outside this account' if @conversation && @conversation.account_id != @playbook.account_id
    raise Unavailable, 'Trigger message is outside the conversation' if message && message.conversation_id != @conversation&.id
  end

  def execute_once(attributes, message_id)
    run = @playbook.runs.create_or_find_by!(trigger_message_id: message_id) { |record| record.assign_attributes(attributes) }
    run.previously_new_record? ? advance(run) : run
  end

  def advance(run)
    while run.running? && run.current_node_id.present?
      unless run.dry_run? || active_conversation?(run)
        run.update!(status: :failed)
        break
      end

      execute_step(run)
    end
    run
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
    run.update!(status: :failed)
    run
  end

  def active_conversation?(run)
    return false unless @conversation.reload.pending?
    return false unless run.account.feature_enabled?(Captain::Playbook::FEATURE)

    responding_to = run.context_state['captain_message_id']
    !responding_to || ::Message.uncached { !@conversation.messages.captain_response_triggering.exists?(id: (responding_to + 1)..) }
  end

  def execute_step(run)
    graph = graph_for(run)
    node = graph.node(run.current_node_id)
    context = run.context_state.deep_dup
    executor = Captain::Playbooks::NodeExecutor.new(run, responding_to_message_id: context['captain_message_id'])
    outcome = executor.execute(node, context)
    return persist_approval_request(run, node, executor, outcome, context) if outcome.is_a?(Captain::Playbooks::NodeExecutor::ApprovalRequest)

    persist_outcome(run, node, graph, outcome, context)
  end

  # A reviewer can act as soon as the request is visible. Commit the request and its resumable step together.
  def persist_approval_request(run, node, executor, request, context)
    run.transaction do
      gate = Captain::Hitl::GatekeeperService.new(
        assistant: @playbook.assistant, conversation: @conversation, playbook_run: run, responding_to_message_id: context['captain_message_id']
      )
      approval = gate.propose!(tool: request.tool, arguments: request.arguments, rationale: request.rationale)
      executor.send_message(I18n.t('captain.hitl.waiting_reply'))
      run.record_step!(node, branch: 'pending_approval', metadata: { approval_id: approval.id }, next_state: { status: :waiting_hitl })
    end
  end

  def persist_outcome(run, node, graph, outcome, context)
    next_id = outcome.status == :running ? graph.next_node_id(node.fetch('id'), outcome.branch) : run.current_node_id
    status = outcome.status == :running ? step_status(next_id, outcome.branch) : outcome.status
    run.record_step!(
      node, branch: outcome.branch, metadata: outcome.metadata,
            next_state: { current_node_id: next_id, status: status, context_state: context }
    )
  end

  def step_status(next_id, branch)
    return :running if next_id
    return :failed if %w[error rejected].include?(branch)

    :completed
  end

  def valid_resume?(run, status)
    run.public_send("#{status}?") && run.playbook_id == @playbook.id && run.conversation_id == @conversation.id &&
      run.account.feature_enabled?(Captain::Playbook::FEATURE) && !run.dry_run?
  end

  def resume_approval_step!(run, approval)
    graph = graph_for(run)
    node = graph.node(run.current_node_id)
    branch = { 'executed' => 'success', 'rejected' => 'rejected' }.fetch(approval.status, 'error')
    context = run.context_state.merge('tool_output' => approval.execution_result)
    outcome = Captain::Playbooks::NodeExecutor::Outcome.new(branch: branch, metadata: { approval_id: approval.id })
    persist_outcome(run, node, graph, outcome, context)
  end

  def claim_user_response(run, message)
    return false unless valid_resume?(run, :waiting_user)
    return false unless message.captain_response_triggering? && message.id > run.context_state['captain_message_id'].to_i

    graph = graph_for(run)
    node = graph.node(run.current_node_id)
    context = run.context_state.merge('captain_message_id' => message.id)
    outcome = user_verification_outcome(run, message)
    persist_outcome(run, node, graph, outcome, context)
    true
  end

  def user_verification_outcome(run, message)
    result = verify_message(message)
    klass = Captain::Playbooks::NodeExecutor::Outcome
    return klass.new(branch: 'verified') if result == :verified
    return klass.new(branch: 'error') if %i[expired locked].include?(result)

    Captain::Playbooks::NodeExecutor.new(run, responding_to_message_id: message.id).send_message(I18n.t('captain.playbooks.verification_retry'))
    klass.new(branch: 'pending_otp', status: :waiting_user)
  end

  def verify_message(message)
    code = message.content.to_s.strip
    verification = Captain::EmailVerification.new(@conversation)
    return :invalid_code unless code.match?(/\A[0-9]{6}\z/)

    result = verification.verify(code)
    return result unless result == :verified

    # A conversation can have only one pending email code. Check the address in case another workflow replaced it.
    current_email = @conversation.contact.reload.email.to_s.strip.downcase
    verification.verified_email == current_email ? :verified : :expired
  end

  def graph_for(run)
    Captain::Playbooks::Graph.new(run.graph_snapshot)
  end
end
