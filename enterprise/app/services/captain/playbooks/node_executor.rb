class Captain::Playbooks::NodeExecutor
  Outcome = Data.define(:branch, :status, :metadata) do
    def initialize(branch: 'default', status: :running, metadata: {})
      super
    end
  end
  ApprovalRequest = Data.define(:tool, :arguments, :rationale)

  def initialize(run, responding_to_message_id:)
    @run = run
    @conversation = run.conversation
    @assistant = run.playbook.assistant
    @responding_to_message_id = responding_to_message_id
  end

  def execute(node, context)
    config = node.fetch('config', {})
    case node.fetch('type')
    when 'trigger', 'condition' then deterministic_outcome(node, config, context)
    when 'otp_verify' then verify_identity(config)
    when 'mcp_tool', 'hitl_gate' then execute_mcp(config, context, require_review: node['type'] == 'hitl_gate')
    when 'llm_reason' then reason(config, context)
    when 'reply' then reply(config, context)
    when 'escalate' then escalate
    end
  end

  def send_message(content)
    return if @run.dry_run?

    @conversation.messages.create!(
      account: @run.account, inbox: @conversation.inbox, sender: @assistant, message_type: :outgoing, content: content
    )
  end

  private

  def deterministic_outcome(node, config, context)
    return Outcome.new if node['type'] == 'trigger'

    Outcome.new(branch: condition_passed?(config, context).to_s)
  end

  def condition_passed?(config, context)
    actual = context_value(context, config.fetch('field'))
    expected = config.fetch('value')
    case config.fetch('operator')
    when 'eq' then actual == expected
    when 'lte' then actual.is_a?(Numeric) && actual <= expected
    when 'gte' then actual.is_a?(Numeric) && actual >= expected
    when 'in' then expected.include?(actual)
    end
  end

  def verify_identity(config)
    return Outcome.new(branch: 'pending_otp', status: :waiting_user, metadata: { simulated: true }) if @run.dry_run?

    verification = Captain::EmailVerification.new(@conversation)
    email = @conversation.contact.email.to_s.strip.downcase
    return Outcome.new(branch: 'verified') if email.present? && verification.verified_email == email
    return Outcome.new(branch: 'error') if email.blank?

    send_verification_email(verification, email, config)
  end

  def send_verification_email(verification, email, config)
    case verification.send_code(email)
    when :already_verified then Outcome.new(branch: 'verified')
    when :sent
      send_message(config['prompt'].presence || I18n.t('captain.playbooks.verification_prompt'))
      Outcome.new(branch: 'pending_otp', status: :waiting_user)
    else
      Outcome.new(branch: 'error')
    end
  end

  def execute_mcp(config, context, require_review:)
    if @run.dry_run?
      context['tool_output'] = { 'simulated' => true, 'tool_name' => config.fetch('tool_name') }
      return Outcome.new(branch: 'success', metadata: { simulated: true })
    end

    server = Captain::McpServer.enabled_for(@assistant).find_by(id: config.fetch('mcp_server_id'))
    return Outcome.new(branch: 'error') unless server

    client = Captain::Mcp::ClientService.new(server, conversation: @conversation)
    tool = client.approved_tool(config.fetch('tool_name'))
    return Outcome.new(branch: 'error') unless tool

    arguments = interpolate_arguments(config.fetch('arguments', {}), context)
    dispatch_mcp(client, tool, arguments, context, { require_review: require_review, rationale: config['rationale'] })
  end

  def dispatch_mcp(client, tool, arguments, context, options)
    hitl_enabled = @run.account.feature_enabled?(Captain::Hitl::GatekeeperService::FEATURE)
    needs_review = options.fetch(:require_review) || Captain::Hitl::GatekeeperService.requires_review?(tool, read_only: tool.read_only?)
    return Outcome.new(branch: 'error') if needs_review && !hitl_enabled
    return request_approval(tool, arguments, options[:rationale]) if needs_review

    call_tool(client, tool, arguments, context)
  end

  def request_approval(tool, arguments, rationale)
    Captain::ToolArguments.new(tool, @conversation).fill(arguments.symbolize_keys)
    ApprovalRequest.new(tool: tool, arguments: arguments, rationale: rationale)
  rescue Captain::ParamSources::Unavailable
    Outcome.new(branch: 'error')
  end

  def call_tool(client, tool, arguments, context)
    result = client.call_tool(
      tool.name, arguments, expected_digest: tool.approved_digest,
                            before_call: -> { 'The customer sent a newer message' if newer_customer_message? }
    )
    context['tool_output'] = result.deep_stringify_keys
    Outcome.new(branch: result[:success] ? 'success' : 'error', metadata: { outcome_unknown: result[:outcome_unknown] == true })
  end

  def newer_customer_message?
    return false unless @responding_to_message_id

    ::Message.uncached { @conversation.messages.captain_response_triggering.exists?(id: (@responding_to_message_id + 1)..) }
  end

  def reason(config, context)
    response = Captain::Llm::RouterService.new(@run.account, assistant: @assistant).chat(
      messages: [
        { role: 'system', content: config.fetch('system_prompt', '') },
        { role: 'user', content: interpolate(config.fetch('user_prompt'), context) }
      ],
      temperature: config.fetch('temperature', 0.2)
    )
    context[config.fetch('output_key', 'llm_output')] = response.fetch(:content).to_s
    Outcome.new(metadata: { model: response[:model], tokens: response[:usage] })
  end

  def reply(config, context)
    response = interpolate(config.fetch('template'), context)
    return Outcome.new(branch: 'empty_reply', status: :failed) if response.blank?

    response = response.truncate(Captain::MessageLengthLimit.for(@conversation)) if @conversation
    context['last_reply'] = response
    send_message(response)
    Outcome.new
  end

  def escalate
    @conversation.bot_handoff! unless @run.dry_run?
    Outcome.new(branch: 'escalate', status: :escalated)
  end

  def interpolate_arguments(value, context)
    case value
    when Hash then value.transform_values { |child| interpolate_arguments(child, context) }
    when Array then value.map { |child| interpolate_arguments(child, context) }
    when String
      entire = value.match(/\A\{\{([\w.]+)\}\}\z/)
      entire ? context_value(context, entire[1]) : interpolate(value, context)
    else value
    end
  end

  def interpolate(template, context)
    template.gsub(/\{\{([\w.]+)\}\}/) { context_value(context, Regexp.last_match(1)).to_s }
  end

  def context_value(context, path)
    path.split('.').reduce(context) { |value, key| value[key] if value.is_a?(Hash) }
  end
end
