require 'agents'

class Captain::Llm::ProviderRunner < Agents::Runner
  def initialize(provider)
    super()
    @provider_context = Captain::Llm::ProviderContext.new(provider)
  end

  private

  def build_chat(_agent)
    @provider_context.chat
  end
end
