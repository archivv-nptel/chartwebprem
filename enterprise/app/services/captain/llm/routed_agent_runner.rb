require 'agents'

# The runner uses the saved provider for the whole agent graph, including
# scenario handoffs, while preserving Captain's existing prompts and tools.
class Captain::Llm::RoutedAgentRunner < Agents::AgentRunner
  def initialize(agents, assistant:)
    super(agents)
    @provider_chain = Captain::Llm::ProviderChain.new(assistant.account, assistant: assistant)
  end

  def run(input, context: {}, max_turns: Agents::Runner::DEFAULT_MAX_TURNS, headers: nil, params: nil)
    @provider_chain.each_available do |provider|
      agents = agents_for_provider(provider)
      starting_agent = agents.fetch(determine_conversation_agent(context).name)
      tool_started = false
      callbacks = @callbacks.merge(tool_start: @callbacks.fetch(:tool_start) + [->(*) { tool_started = true }])
      scoped_runner = Captain::Llm::ProviderRunner.new(provider)
      result = scoped_runner.run(starting_agent, input, context: context, registry: agents, max_turns: max_turns,
                                                        headers: headers, params: params, callbacks: callbacks)
      raise result.error if retryable?(result.error, tool_started)

      # A completed tool may have performed a write. Surface a sanitized
      # provider failure to Captain's normal handoff path without replay.
      raise Captain::Llm::ProviderChain::Unavailable, 'Captain provider failed after tool execution' if provider_error?(result.error)

      result
    end
  end

  private

  def agents_for_provider(provider)
    agents = @agents.index_by(&:name).transform_values do |agent|
      agent.clone(model: provider.model_id, protocol: nil, thinking: nil, params: nil, handoff_agents: [])
    end
    @agents.each do |agent|
      targets = agent.handoff_agents.map { |target| agents.fetch(target.name) }
      agents.fetch(agent.name).register_handoffs(*targets) if targets.any?
    end
    agents
  end

  def retryable?(error, tool_started)
    !tool_started && provider_error?(error)
  end

  def provider_error?(error)
    Captain::Llm::ProviderChain::ERRORS.any? { |error_type| error.is_a?(error_type) }
  end
end
