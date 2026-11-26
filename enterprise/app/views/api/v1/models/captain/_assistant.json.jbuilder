json.account_id resource.account_id
json.avatar_url resource.avatar_url
json.config resource.config.merge(
  'auto_resolve_mode' => resource.auto_resolve_mode,
  'auto_resolve_after' => resource.inactivity_threshold_minutes,
  'send_inactivity_resolution_message' => resource.send_inactivity_resolution_message?
)
json.created_at resource.created_at.to_i
json.description resource.description
json.guardrails resource.guardrails
json.id resource.id
json.name resource.name
json.response_guidelines resource.response_guidelines
json.updated_at resource.updated_at.to_i

json.llm_provider_config_id resource.llm_provider_config_id if Current.account&.feature_enabled?('captain_byom_routing')
if Current.account&.feature_enabled?('captain_swarm_handoffs')
  json.swarm_role resource.swarm_role
  json.swarm_capabilities resource.swarm_capabilities
end
