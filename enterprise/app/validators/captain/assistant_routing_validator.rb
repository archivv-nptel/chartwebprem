class Captain::AssistantRoutingValidator < ActiveModel::Validator
  def validate(assistant)
    validate_capabilities(assistant) if assistant.will_save_change_to_swarm_capabilities?
    validate_provider_account(assistant) if assistant.will_save_change_to_llm_provider_config_id?
  end

  private

  def validate_capabilities(assistant)
    capabilities = assistant.swarm_capabilities
    return if capabilities.is_a?(Array) && capabilities.size <= 10 && capabilities.all? { |name| valid_capability?(name) }

    assistant.errors.add(:swarm_capabilities, :invalid)
  end

  def valid_capability?(name)
    name.is_a?(String) && name.present? && name.size <= 120
  end

  def validate_provider_account(assistant)
    return unless assistant.llm_provider_config_id
    return if assistant.llm_provider_config&.account_id == assistant.account_id

    assistant.errors.add(:llm_provider_config, :invalid)
  end
end
