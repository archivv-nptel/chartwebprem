class Captain::Llm::RouterService
  def initialize(account, assistant: nil)
    @account = account
    @assistant = assistant
  end

  def chat(messages:, tools: [], temperature: 0.2, model_override: nil, feature: 'assistant')
    if @account.feature_enabled?('captain_byom_routing')
      chain = Captain::Llm::ProviderChain.new(@account, assistant: @assistant, feature: feature)
      return chain.each_available(model_override: model_override) do |provider|
        chat = Captain::Llm::ProviderContext.new(provider).chat
        generate(chat, messages, tools, temperature)
      end
    end

    generate(platform_chat(feature, model_override), messages, tools, temperature)
  end

  def test_connection(provider)
    raise ArgumentError, 'Provider belongs to another account' if provider.account_id != @account.id

    generate(Captain::Llm::ProviderContext.new(provider).chat, [{ role: 'user', content: 'Respond with OK.' }], [], 0.0)
  end

  private

  def platform_chat(feature, model_override)
    ::Llm::Config.initialize!
    route = ::Llm::FeatureRouter.resolve(feature: feature, account: @account)
    model = model_override.presence || route.fetch(:model)
    provider = ::Llm::Models.provider_for(model)
    provider ||= route[:provider] if model == route[:model]
    raise ArgumentError, 'Model is unavailable for this feature' if provider.blank?

    RubyLLM.chat(model: model, provider: provider, assume_model_exists: route[:source] == :installation_override)
  end

  def generate(chat, messages, tools, temperature)
    chat.with_temperature(temperature).with_tools(*tools)
    chat.messages = messages.map { |message| message.symbolize_keys.slice(:role, :content) }
    response = chat.generate

    {
      content: response.content.to_s,
      tool_calls: response.tool_calls&.values&.map(&:to_h) || [],
      model: response.model,
      usage: { prompt_tokens: response.tokens.input, completion_tokens: response.tokens.output }
    }
  end
end
