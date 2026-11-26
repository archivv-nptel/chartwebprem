# RubyLLM's transport uses its process logger even in a scoped context.
# Suppress request bodies for tenant-provider calls without changing global log levels.
class Captain::Llm::ProviderChat < RubyLLM::Chat
  def generate(...)
    logger = RubyLLM.logger
    return super unless logger.respond_to?(:silence)

    logger.silence(Logger::FATAL) { super }
  end
end
