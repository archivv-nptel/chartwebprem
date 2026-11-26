# Routes to at most three eligible providers. A ZDR requirement on the primary
# route carries through failover. Turn callers decide when it is safe to retry.
class Captain::Llm::ProviderChain
  MAX_PROVIDERS = 3
  MAX_FAILURES = 5
  OPEN_INTERVAL_SECONDS = 60
  ERRORS = [RubyLLM::Error, RubyLLM::ConfigurationError, Faraday::Error, SafeFetch::Error,
            Captain::Mcp::SafeFaradayAdapter::ResponseTooLarge].freeze

  class Unavailable < StandardError; end

  def initialize(account, assistant: nil, feature: 'assistant')
    raise ArgumentError, 'Assistant belongs to another account' if assistant && assistant.account_id != account.id

    @account = account
    @assistant = assistant
    @feature = feature
  end

  def each_available(model_override: nil)
    eligible_providers(model_override).each do |provider|
      next if Redis::Alfred.get(cache_key(provider)).to_i >= MAX_FAILURES

      result = yield provider
      Redis::Alfred.delete(cache_key(provider))
      return result
    rescue *ERRORS => e
      note_failure(provider, e)
    end
    raise Unavailable, 'No eligible Captain model provider answered'
  end

  private

  def eligible_providers(model_override)
    providers = account_providers
    pinned = pinned_provider
    primary = providers.first
    providers = providers.where(zero_data_retention: true) if pinned&.zero_data_retention? || primary&.zero_data_retention?
    providers = providers.where(model_id: model_override) if model_override.present?
    prioritize_pinned(providers, pinned)
  end

  def prioritize_pinned(providers, pinned)
    return providers.limit(MAX_PROVIDERS).to_a unless pinned

    preferred = providers.find_by(id: pinned.id)
    return providers.limit(MAX_PROVIDERS).to_a unless preferred

    [preferred] + providers.where.not(id: preferred.id).limit(MAX_PROVIDERS - 1).to_a
  end

  def pinned_provider
    return unless @assistant&.llm_provider_config_id

    @account.captain_llm_provider_configs.find_by(id: @assistant.llm_provider_config_id)
  end

  def account_providers
    rules = Captain::LlmProviderConfig.arel_table[:routing_rules]
    task = Arel::Nodes::NamedFunction.new('jsonb_extract_path_text', [rules, Arel::Nodes.build_quoted('task')])
    @account.captain_llm_provider_configs.ordered_active.where(task.eq(nil).or(task.eq(@feature)))
  end

  def note_failure(provider, error)
    key = cache_key(provider)
    Redis::Alfred.with do |redis|
      redis.multi do |transaction|
        transaction.incr(key)
        transaction.expire(key, OPEN_INTERVAL_SECONDS)
      end
    end
    Rails.logger.warn("[Captain BYOM] Provider #{provider.id} failed with #{error.class.name}")
  end

  def cache_key(provider)
    "captain/llm/provider-failures/#{provider.cache_key_with_version}"
  end
end
